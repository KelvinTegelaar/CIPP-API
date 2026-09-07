# Pester tests for Get-CIPPGroupsReport -AsRawJson
# Validates that a page is stitched from the stored blobs verbatim (no member array is
# ever deserialized), with per-row CacheTimestamp and (AllTenants only) Tenant spliced in.

BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))

    # Stub the helpers the exercised path touches so Pester's Mock has a command to replace.
    function Get-CIPPDbItemPage { param($TenantFilter, $Type, $PageSize, $ContinuationToken) }
    function Get-CIPPDbItem { param($TenantFilter, $Type) }
    function Get-Tenants { param($TenantFilter, [switch]$IncludeErrors) }
    function Write-LogMessage { param($API, $tenant, $message, $sev) }

    . (Join-Path $RepoRoot 'Modules/CIPPCore/Public/Get-CIPPGroupsReport.ps1')

    function New-GroupBlob {
        param([string]$Id, [string[]]$Upns)
        $members = @(foreach ($u in $Upns) { [PSCustomObject]@{ id = $u; userPrincipalName = $u } })
        [PSCustomObject]@{
            id          = $Id
            displayName = "Group $Id"
            members     = $members
            membersCsv  = ($Upns -join ',')
        } | ConvertTo-Json -Depth 10 -Compress
    }

    function New-PageItem {
        param([string]$Tenant, [string]$Blob, $Timestamp)
        [PSCustomObject]@{ PartitionKey = $Tenant; Timestamp = $Timestamp; Data = $Blob }
    }
}

Describe 'Get-CIPPGroupsReport -AsRawJson' {
    It 'stitches blobs verbatim and splices Tenant + CacheTimestamp for AllTenants' {
        $ts = [datetimeoffset]'2024-05-01T10:00:00Z'
        $blobA = New-GroupBlob -Id 'g1' -Upns @('a@contoso.com', 'b@contoso.com')
        $blobB = New-GroupBlob -Id 'g2' -Upns @('c@fabrikam.com')
        $page = [PSCustomObject]@{
            Items     = @(
                (New-PageItem -Tenant 'contoso.onmicrosoft.com' -Blob $blobA -Timestamp $ts),
                (New-PageItem -Tenant 'fabrikam.onmicrosoft.com' -Blob $blobB -Timestamp $ts)
            )
            NextToken = 'fabrikam.onmicrosoft.com|Groups-xyz'
        }
        Mock -CommandName Get-CIPPDbItemPage -MockWith { $page }.GetNewClosure()

        $result = Get-CIPPGroupsReport -TenantFilter 'AllTenants' -PageSize 100 -AsRawJson

        $result.NextToken | Should -Be 'fabrikam.onmicrosoft.com|Groups-xyz'
        # The stored blob (minus its closing brace) must appear byte-for-byte — proof the
        # member array was streamed, not parsed and rebuilt. Literal Contains, not -BeLike:
        # the members array's [ ] are wildcard metacharacters.
        $result.CippPagedJson.Contains($blobA.Substring(0, $blobA.Length - 1)) | Should -BeTrue

        $parsed = $result.CippPagedJson | ConvertFrom-Json
        $parsed | Should -HaveCount 2
        $parsed[0].members | Should -HaveCount 2
        $parsed[0].members[0].userPrincipalName | Should -Be 'a@contoso.com'
        $parsed[0].membersCsv | Should -Be 'a@contoso.com,b@contoso.com'
        $parsed[0].Tenant | Should -Be 'contoso.onmicrosoft.com'
        $parsed[1].Tenant | Should -Be 'fabrikam.onmicrosoft.com'
        $parsed[0].CacheTimestamp | Should -Not -BeNullOrEmpty
    }

    It 'does not splice a Tenant field for a single-tenant read' {
        $blob = New-GroupBlob -Id 'g1' -Upns @('a@contoso.com')
        $page = [PSCustomObject]@{
            Items     = @((New-PageItem -Tenant 'contoso.onmicrosoft.com' -Blob $blob -Timestamp ([datetimeoffset]::UtcNow)))
            NextToken = $null
        }
        Mock -CommandName Get-CIPPDbItemPage -MockWith { $page }.GetNewClosure()

        $result = Get-CIPPGroupsReport -TenantFilter 'contoso.onmicrosoft.com' -PageSize 100 -AsRawJson
        $parsed = $result.CippPagedJson | ConvertFrom-Json

        $parsed.PSObject.Properties.Name | Should -Not -Contain 'Tenant'
        $parsed.CacheTimestamp | Should -Not -BeNullOrEmpty
        $result.NextToken | Should -BeNullOrEmpty
    }

    It 'skips empty or malformed blobs' {
        $good = New-GroupBlob -Id 'g1' -Upns @('a@contoso.com')
        $page = [PSCustomObject]@{
            Items     = @(
                (New-PageItem -Tenant 'contoso.onmicrosoft.com' -Blob '' -Timestamp ([datetimeoffset]::UtcNow)),
                (New-PageItem -Tenant 'contoso.onmicrosoft.com' -Blob '   ' -Timestamp ([datetimeoffset]::UtcNow)),
                (New-PageItem -Tenant 'contoso.onmicrosoft.com' -Blob $good -Timestamp ([datetimeoffset]::UtcNow))
            )
            NextToken = $null
        }
        Mock -CommandName Get-CIPPDbItemPage -MockWith { $page }.GetNewClosure()

        $result = Get-CIPPGroupsReport -TenantFilter 'AllTenants' -PageSize 100 -AsRawJson
        $parsed = @($result.CippPagedJson | ConvertFrom-Json)

        $parsed | Should -HaveCount 1
        $parsed[0].id | Should -Be 'g1'
    }
}
