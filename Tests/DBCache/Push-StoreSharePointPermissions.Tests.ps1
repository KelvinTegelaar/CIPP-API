# Pester tests for Push-StoreSharePointPermissions
#
# The store step for the SharePoint permissions scan. These lock the behaviour that keeps a large
# tenant's report alive instead of letting it expire under the 30-day reporting retention:
#  - a run where a whole batch failed (sites missing from the fan-in) still writes the sites that
#    came back and carries the missing ones over from the prior cache, flagged Skipped;
#  - a run that collected nothing writes nothing, so stale data is not re-stamped as fresh;
#  - rows are streamed into one Add-CIPPDbItem invocation (memory) and the prior cache is read only
#    for the sites being restored, by RowKey prefix.

BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
    $FunctionPath = Get-ChildItem -Path (Join-Path $RepoRoot 'Modules') -Recurse -Filter 'Push-StoreSharePointPermissions.ps1' -File -ErrorAction SilentlyContinue |
        Select-Object -First 1 -ExpandProperty FullName
    if (-not $FunctionPath) { throw 'Could not locate Push-StoreSharePointPermissions.ps1 under Modules/' }

    # Minimal stubs so Mock has commands to replace.
    function Write-LogMessage { param($API, $tenant, $message, $sev, $LogData) }
    function Add-CIPPDbItem {
        [CmdletBinding()]
        param(
            [Parameter(Mandatory)][string]$TenantFilter,
            [Parameter(Mandatory)][string]$Type,
            [Parameter(Mandatory, ValueFromPipeline)][AllowNull()][AllowEmptyCollection()]$InputObject,
            [switch]$Count,
            [switch]$AddCount,
            [switch]$Append,
            [switch]$ClearOnEmpty,
            [string]$RunId
        )
    }
    function Get-CippTable { param($tablename) @{} }
    function Get-CIPPAzDataTableEntity { param([string]$Filter) @() }
    function Get-Tenants { param($TenantFilter, [switch]$IncludeErrors) }
    function Get-CippException { param($Exception) }

    . $FunctionPath

    function New-SiteRow {
        param($Id, $Status = 'Full')
        [PSCustomObject]@{ rowType = 'Site'; id = "${Id}_site"; siteId = $Id; siteName = "site-$Id"; collectionStatus = $Status }
    }
    function New-Assignment {
        param($Id, $SiteId)
        [PSCustomObject]@{ rowType = 'Assignment'; id = $Id; siteId = $SiteId; principalId = 'p1'; permissionLevel = 'Read' }
    }
    function New-SiteResult {
        param($Id, $Status = 'Full', $Assignments = 0)
        $Rows = @(for ($i = 1; $i -le $Assignments; $i++) { New-Assignment -Id "${Id}_a$i" -SiteId $Id })
        [PSCustomObject]@{
            SiteId           = $Id
            CollectionStatus = $Status
            SiteRow          = (New-SiteRow -Id $Id -Status $Status)
            Rows             = @($Rows)
        }
    }
    function New-WorkItem {
        param($SiteResults, [int]$ExpectedSiteCount, $ExpectedSiteIds)
        @{
            Parameters = @{ TenantFilter = 'contoso.onmicrosoft.com'; ExpectedSiteCount = $ExpectedSiteCount; ExpectedSiteIds = $ExpectedSiteIds }
            Results    = @(@{ Sites = @($SiteResults) })
        }
    }
    # Prior-cache entity rows (as stored: one Site row + N Assignment rows, Data is compressed JSON).
    function New-PriorEntities {
        param($SiteId, [int]$Assignments, [int]$Libraries = 3)
        $Entities = [System.Collections.Generic.List[object]]::new()
        $Entities.Add([PSCustomObject]@{ Data = ([PSCustomObject]@{ rowType = 'Site'; id = "${SiteId}_site"; siteId = $SiteId; siteName = "prior-$SiteId"; siteUrl = "https://x/$SiteId"; collectionStatus = 'Full'; librariesScanned = $Libraries; librariesWithUniquePermissions = 1 } | ConvertTo-Json -Compress) })
        for ($i = 1; $i -le $Assignments; $i++) {
            $Entities.Add([PSCustomObject]@{ Data = ([PSCustomObject]@{ rowType = 'Assignment'; id = "${SiteId}_prior_a$i"; siteId = $SiteId; principalId = "pp$i"; permissionLevel = 'Read' } | ConvertTo-Json -Compress) })
        }
        @($Entities)
    }
}

Describe 'Push-StoreSharePointPermissions' {
    BeforeEach {
        $script:Rows = [System.Collections.Generic.List[object]]::new()
        Mock -CommandName Write-LogMessage -MockWith { }
        Mock -CommandName Get-CippException -MockWith { @{} }
        Mock -CommandName Get-CippTable -MockWith { @{} }
        Mock -CommandName Add-CIPPDbItem -MockWith {
            $script:Rows.Add([PSCustomObject]@{ Type = $Type; AddCount = $AddCount.IsPresent; Tenant = $TenantFilter; Row = $InputObject })
        }
    }

    It 'writes every site and assignment row on a complete run, with no prior-cache read' {
        $Item = New-WorkItem -ExpectedSiteCount 2 -ExpectedSiteIds @('s1', 's2') -SiteResults @(
            (New-SiteResult -Id 's1' -Assignments 2),
            (New-SiteResult -Id 's2' -Assignments 1)
        )
        Mock -CommandName Get-CIPPAzDataTableEntity -MockWith { @() }

        Push-StoreSharePointPermissions -Item $Item

        # 2 site rows + 3 assignment rows, streamed one per invocation.
        Should -Invoke Add-CIPPDbItem -Times 5 -Exactly -ParameterFilter {
            $AddCount.IsPresent -and $Type -eq 'SharePointPermissions' -and $TenantFilter -eq 'contoso.onmicrosoft.com'
        }
        @($script:Rows | Where-Object { $_.Row.rowType -eq 'Assignment' }).Count | Should -Be 3
        Should -Invoke Get-CIPPAzDataTableEntity -Times 0 -Exactly
        Should -Invoke Write-LogMessage -Times 1 -Exactly -ParameterFilter { $sev -eq 'Info' -and $message -like 'Cached 3 SharePoint permission assignments*' }
    }

    It 'carries a missing batch over from the prior cache instead of discarding the run' {
        # s1, s2 came back; s3 was expected but its batch did not return.
        $Item = New-WorkItem -ExpectedSiteCount 3 -ExpectedSiteIds @('s1', 's2', 's3') -SiteResults @(
            (New-SiteResult -Id 's1' -Assignments 1),
            (New-SiteResult -Id 's2' -Assignments 1)
        )
        Mock -CommandName Get-CIPPAzDataTableEntity -MockWith {
            if ($Filter -match 'SharePointPermissions-s3_') { return (New-PriorEntities -SiteId 's3' -Assignments 2 -Libraries 5) }
            @()
        }

        Push-StoreSharePointPermissions -Item $Item

        # s1 site+1, s2 site+1, s3 synthetic site + 2 restored = 3 site rows + 4 assignment rows.
        @($script:Rows | Where-Object { $_.Row.rowType -eq 'Site' }).Count | Should -Be 3
        @($script:Rows | Where-Object { $_.Row.rowType -eq 'Assignment' }).Count | Should -Be 4

        $Synth = @($script:Rows | Where-Object { $_.Row.rowType -eq 'Site' -and $_.Row.siteId -eq 's3' })
        $Synth.Count | Should -Be 1
        $Synth[0].Row.collectionStatus | Should -Be 'Skipped'
        $Synth[0].Row.librariesScanned | Should -Be 5
        $Synth[0].Row.collectionError | Should -BeLike '*not returned by its collection batch*'

        # Only the missing site is read from the prior cache, by its own RowKey prefix.
        Should -Invoke Get-CIPPAzDataTableEntity -Times 1 -Exactly
        Should -Invoke Write-LogMessage -Times 1 -Exactly -ParameterFilter { $sev -eq 'Warning' -and $message -like '*1 missing (carried over)*' }
    }

    It 'restores a returned-Skipped site''s assignments from the prior cache' {
        $Item = New-WorkItem -ExpectedSiteCount 2 -ExpectedSiteIds @('s1', 's2') -SiteResults @(
            (New-SiteResult -Id 's1' -Assignments 1),
            (New-SiteResult -Id 's2' -Status 'Skipped' -Assignments 0)
        )
        Mock -CommandName Get-CIPPAzDataTableEntity -MockWith {
            if ($Filter -match 'SharePointPermissions-s2_') { return (New-PriorEntities -SiteId 's2' -Assignments 2) }
            @()
        }

        Push-StoreSharePointPermissions -Item $Item

        # s1 site + 1 asg, s2 (skipped) site + 2 restored asg = 2 site rows + 3 assignment rows.
        @($script:Rows | Where-Object { $_.Row.rowType -eq 'Site' }).Count | Should -Be 2
        @($script:Rows | Where-Object { $_.Row.rowType -eq 'Assignment' }).Count | Should -Be 3
        Should -Invoke Get-CIPPAzDataTableEntity -Times 1 -Exactly
    }

    It 'writes nothing when no site was collected, so a stale cache is not re-stamped' {
        $Item = New-WorkItem -ExpectedSiteCount 2 -ExpectedSiteIds @('s1', 's2') -SiteResults @(
            (New-SiteResult -Id 's1' -Status 'Skipped'),
            (New-SiteResult -Id 's2' -Status 'Skipped')
        )

        Push-StoreSharePointPermissions -Item $Item

        Should -Invoke Add-CIPPDbItem -Times 0 -Exactly
        Should -Invoke Write-LogMessage -Times 1 -Exactly -ParameterFilter { $sev -eq 'Error' -and $message -like '*no sites collected this run*' }
    }

    It 'without an expected-site list, an incomplete run preserves the prior cache (no partial write)' {
        $Item = New-WorkItem -ExpectedSiteCount 3 -ExpectedSiteIds $null -SiteResults @(
            (New-SiteResult -Id 's1' -Assignments 1),
            (New-SiteResult -Id 's2' -Assignments 1)
        )

        Push-StoreSharePointPermissions -Item $Item

        Should -Invoke Add-CIPPDbItem -Times 0 -Exactly
        Should -Invoke Write-LogMessage -Times 1 -Exactly -ParameterFilter { $sev -eq 'Warning' -and $message -like '*no expected-site list to reconcile*' }
    }

    It 'without an expected-site list, a complete run still writes (back-compat path)' {
        $Item = New-WorkItem -ExpectedSiteCount 2 -ExpectedSiteIds $null -SiteResults @(
            (New-SiteResult -Id 's1' -Assignments 1),
            (New-SiteResult -Id 's2' -Assignments 1)
        )
        Mock -CommandName Get-CIPPAzDataTableEntity -MockWith { @() }

        Push-StoreSharePointPermissions -Item $Item

        Should -Invoke Add-CIPPDbItem -Times 4 -Exactly -ParameterFilter { $Type -eq 'SharePointPermissions' }
        Should -Invoke Get-CIPPAzDataTableEntity -Times 0 -Exactly
    }
}
