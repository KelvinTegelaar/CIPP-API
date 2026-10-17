# Pester tests for Push-StoreStorageCleanupScan: a lost batch or a Skipped site keeps its prior rows
# instead of discarding the run, and a run that collected nothing writes nothing.

BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
    $FunctionPath = Get-ChildItem -Path (Join-Path $RepoRoot 'Modules') -Recurse -Filter 'Push-StoreStorageCleanupScan.ps1' -File |
        Select-Object -First 1 -ExpandProperty FullName

    function Write-LogMessage { param($API, $tenant, $message, $sev, $LogData) }
    function Add-CIPPDbItem { param($TenantFilter, $Type, $TableName, $Data, [switch]$AddCount) }
    function New-CIPPDbRequest { param($TenantFilter, $Type, $TableName) }
    function Get-CippException { param($Exception) }

    . $FunctionPath

    function New-SiteResult {
        param($Id, $Status = 'Full', [int]$Libraries = 1)
        [PSCustomObject]@{
            SiteId           = $Id
            CollectionStatus = $Status
            SiteRow          = [PSCustomObject]@{ rowType = 'Site'; id = "${Id}_site"; siteId = $Id; siteUrl = "https://x/$Id"; collectionStatus = $Status; collectionError = if ($Status -eq 'Skipped') { 'throttled' }; recycleTotalBytes = $null }
            Rows             = @(if ($Status -ne 'Skipped') { for ($i = 1; $i -le $Libraries; $i++) { [PSCustomObject]@{ rowType = 'Library'; id = "${Id}_l$i"; siteId = $Id; versionEstimateBytes = 10 } } })
        }
    }
    function New-WorkItem {
        param($SiteResults, [int]$ExpectedSiteCount, $ExpectedSiteIds)
        @{
            Parameters = @{ TenantFilter = 'contoso.onmicrosoft.com'; ExpectedSiteCount = $ExpectedSiteCount; ExpectedSiteIds = $ExpectedSiteIds }
            Results    = @(@{ Sites = @($SiteResults) })
        }
    }
    function New-PriorRows {
        param($Id)
        [PSCustomObject]@{ rowType = 'Site'; id = "${Id}_site"; siteId = $Id; siteUrl = "https://x/$Id"; collectionStatus = 'Full'; recycleTotalBytes = 500 }
        [PSCustomObject]@{ rowType = 'Library'; id = "${Id}_old"; siteId = $Id; versionEstimateBytes = 99 }
    }
}

Describe 'Push-StoreStorageCleanupScan' {
    BeforeEach {
        Mock -CommandName Write-LogMessage -MockWith { }
        Mock -CommandName Get-CippException -MockWith { @{} }
        Mock -CommandName Add-CIPPDbItem -MockWith { $script:Written = @($Data) }
        Mock -CommandName New-CIPPDbRequest -MockWith { @((New-PriorRows 's2'); (New-PriorRows 's3')) }
        $script:Written = $null
    }

    It 'writes a complete run to its own table without reading the prior scan' {
        Push-StoreStorageCleanupScan -Item (New-WorkItem -ExpectedSiteCount 2 -ExpectedSiteIds @('s1', 's2') -SiteResults @((New-SiteResult 's1' -Libraries 2), (New-SiteResult 's2')))

        Should -Invoke Add-CIPPDbItem -Times 1 -Exactly -ParameterFilter { $TableName -eq 'CippStorageCleanupScan' -and $Type -eq 'StorageCleanupScan' -and $AddCount }
        Should -Invoke New-CIPPDbRequest -Times 0 -Exactly
        $script:Written.Count | Should -Be 5
    }

    It 'carries a lost batch and a Skipped site over from the prior scan' {
        # s2 came back Skipped, s3's batch never returned.
        Push-StoreStorageCleanupScan -Item (New-WorkItem -ExpectedSiteCount 3 -ExpectedSiteIds @('s1', 's2', 's3') -SiteResults @((New-SiteResult 's1'), (New-SiteResult 's2' -Status 'Skipped')))

        $Sites = @($script:Written | Where-Object rowType -EQ 'Site')
        $Sites.Count | Should -Be 3
        foreach ($Id in 's2', 's3') {
            $Site = $Sites | Where-Object siteId -EQ $Id
            $Site.collectionStatus | Should -Be 'Skipped'
            $Site.recycleTotalBytes | Should -Be 500
            @($script:Written | Where-Object { $_.rowType -eq 'Library' -and $_.siteId -eq $Id }).versionEstimateBytes | Should -Be 99
        }
        ($Sites | Where-Object siteId -EQ 's2').collectionError | Should -Be 'throttled'
        ($Sites | Where-Object siteId -EQ 's3').collectionError | Should -BeLike '*not returned by its collection batch*'
        Should -Invoke New-CIPPDbRequest -Times 1 -Exactly -ParameterFilter { $TableName -eq 'CippStorageCleanupScan' }
    }

    It 'keeps a never-collected missing site visible as Skipped' {
        Mock -CommandName New-CIPPDbRequest -MockWith { @() }
        Push-StoreStorageCleanupScan -Item (New-WorkItem -ExpectedSiteCount 2 -ExpectedSiteIds @('s1', 's9') -SiteResults @((New-SiteResult 's1')))

        ($script:Written | Where-Object siteId -EQ 's9').collectionStatus | Should -Be 'Skipped'
    }

    It 'writes nothing when no site was collected' {
        Push-StoreStorageCleanupScan -Item (New-WorkItem -ExpectedSiteCount 2 -ExpectedSiteIds @('s1', 's2') -SiteResults @((New-SiteResult 's1' -Status 'Skipped')))

        Should -Invoke Add-CIPPDbItem -Times 0 -Exactly
    }

    It 'without an expected-site list, refuses an incomplete run' {
        { Push-StoreStorageCleanupScan -Item (New-WorkItem -ExpectedSiteCount 2 -ExpectedSiteIds $null -SiteResults @((New-SiteResult 's1'))) } | Should -Throw '*completeness check failed*'
        Should -Invoke Add-CIPPDbItem -Times 0 -Exactly
    }
}
