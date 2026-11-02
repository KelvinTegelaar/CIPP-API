# Pester tests for Set-CIPPDBCacheServicePrincipalSignInActivities
# An empty report is written as an authoritative empty set; a failed read writes nothing and rethrows,
# so no app is reported idle because the report could not be read.

BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))

    function New-GraphGetRequest { param($uri, $tenantid, [switch]$Stream) }
    function Add-CIPPDbItem {
        [CmdletBinding()]
        param($TenantFilter, $Type, [Parameter(ValueFromPipeline = $true)]$InputObject, $Data, [switch]$AddCount, [switch]$ClearOnEmpty)
        process { if ($InputObject) { $script:Written.Add($InputObject) } }
        end { if ($PSBoundParameters.ContainsKey('Data')) { $script:EmptyWrites++ } }
    }
    function Write-LogMessage { param($API, $tenant, $message, $sev, $LogData) }

    . (Join-Path $RepoRoot 'Modules/CIPPDB/Public/DBCache/Set-CIPPDBCacheServicePrincipalSignInActivities.ps1')
}

Describe 'Set-CIPPDBCacheServicePrincipalSignInActivities' {
    BeforeEach {
        $script:Written = [System.Collections.Generic.List[object]]::new()
        $script:EmptyWrites = 0
        Mock Write-LogMessage { }
    }

    It 'streams every row from the sign-in activity report into the cache' {
        Mock New-GraphGetRequest { [pscustomobject]@{ appId = 'a' }; [pscustomobject]@{ appId = 'b' } }

        Set-CIPPDBCacheServicePrincipalSignInActivities -TenantFilter 'contoso.onmicrosoft.com'

        $script:Written.appId | Should -Be @('a', 'b')
        Should -Invoke New-GraphGetRequest -Times 1 -Exactly -ParameterFilter { $uri -eq 'https://graph.microsoft.com/beta/reports/servicePrincipalSignInActivities' }
    }

    It 'records an empty report as an empty set' {
        Mock New-GraphGetRequest { }

        Set-CIPPDBCacheServicePrincipalSignInActivities -TenantFilter 'contoso.onmicrosoft.com'

        $script:EmptyWrites | Should -Be 1
    }

    It 'writes nothing and rethrows when the report cannot be read' {
        Mock New-GraphGetRequest { throw 'Tenant does not have a SKU required for this feature' }

        { Set-CIPPDBCacheServicePrincipalSignInActivities -TenantFilter 'contoso.onmicrosoft.com' } | Should -Throw '*SKU*'
        $script:Written.Count | Should -Be 0
        $script:EmptyWrites | Should -Be 0
        Should -Invoke Write-LogMessage -Times 1 -ParameterFilter { $sev -eq 'Error' }
    }
}
