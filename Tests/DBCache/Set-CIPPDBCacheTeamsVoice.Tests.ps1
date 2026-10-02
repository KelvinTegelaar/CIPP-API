BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
    . (Join-Path $RepoRoot 'Modules/CIPPDB/Public/DBCache/Set-CIPPDBCacheTeamsVoice.ps1')

    function Get-Tenants { param($TenantFilter) [pscustomobject]@{ customerId = 'tid' } }
    function New-GraphGetRequest { param($uri, $tenantid, [switch]$Stream) }
    function Get-CippTeamsLocationLookup { param($TenantFilter) @{ 'loc-1' = 'Head office' } }
    function New-TeamsRequestV2 { param($TenantFilter, $Path, $QueryParameters, $AdditionalHeaders) }
    function Write-LogMessage { param([Parameter(ValueFromRemainingArguments)]$Rest) }
    function Get-CippException { param($Exception) }
    function Add-CIPPDbItem { param($TenantFilter, $Type, $Data, [switch]$AddCount) $script:Written = @($Data) }
}

Describe 'Set-CIPPDBCacheTeamsVoice' {
    BeforeEach {
        $script:Written = $null
        Mock New-GraphGetRequest {
            [pscustomobject]@{ id = 'u-1'; userPrincipalName = 'a@contoso.com'; displayName = 'A' }
            [pscustomobject]@{ id = 'u-2'; userPrincipalName = 'b@contoso.com'; displayName = 'B' }
        }
        Mock New-TeamsRequestV2 {
            [pscustomobject]@{ TelephoneNumbers = @(
                    [pscustomobject]@{ TelephoneNumber = '+1'; TargetId = 'u-2'; LocationId = 'loc-1'; AcquisitionDate = '2025-01-02T03:04:05Z' }
                    [pscustomobject]@{ TelephoneNumber = '+2'; TargetId = 'u-9'; LocationId = $null; AcquisitionDate = $null }
                    [pscustomobject]@{ TelephoneNumber = '+3'; TargetId = $null; LocationId = $null; AcquisitionDate = $null }
                ) }
        }
    }

    It 'assigns each number to its user and marks the rest unassigned' {
        Set-CIPPDBCacheTeamsVoice -TenantFilter 'contoso.com'

        $script:Written.Count | Should -Be 3
        $script:Written[0].AssignedTo.userPrincipalName | Should -Be 'b@contoso.com'
        $script:Written[0].EmergencyLocation | Should -Be 'Head office'
        $script:Written[0].AcquisitionDate | Should -Be '2025-01-02'
        $script:Written[1].AssignedTo | Should -Be 'Unassigned'
        $script:Written[2].AssignedTo | Should -Be 'Unassigned'
        $script:Written[2].AcquisitionDate | Should -Be 'Unknown'
    }
}
