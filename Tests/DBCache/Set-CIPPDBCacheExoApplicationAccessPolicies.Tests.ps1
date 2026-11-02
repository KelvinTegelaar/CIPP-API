# Pester tests for Set-CIPPDBCacheExoApplicationAccessPolicies and Get-CIPPExoApplicationAccessPolicy
# A policy naming several apps becomes one row per app, keyed apart; an empty read is recorded as an empty set and a
# failed read writes nothing and rethrows.

BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))

    function New-ExoRequest { param($tenantid, $cmdlet, $cmdParams) }
    function Add-CIPPDbItem { param($TenantFilter, $Type, $Data, [switch]$AddCount, [switch]$ClearOnEmpty) }
    function Write-LogMessage { param($API, $tenant, $message, $sev, $LogData) }

    . (Join-Path $RepoRoot 'Modules/CIPPCore/Public/AppPermissions/Get-CIPPExoApplicationAccessPolicy.ps1')
    . (Join-Path $RepoRoot 'Modules/CIPPDB/Public/DBCache/Set-CIPPDBCacheExoApplicationAccessPolicies.ps1')
}

Describe 'Get-CIPPExoApplicationAccessPolicy' {
    It 'returns one row per app a policy names, with an id per app' {
        Mock New-ExoRequest {
            [pscustomobject]@{ Identity = 'contoso\pol-1'; AppId = @('app-1', 'app-2'); AccessRight = 'DenyAccess'; ScopeName = 'Executives'; ScopeIdentity = 'Executives'; IsValid = $true }
            [pscustomobject]@{ Identity = 'contoso\pol-2'; AppId = 'app-3'; AccessRight = 'RestrictAccess'; ScopeName = 'Sales'; IsValid = $false }
        }

        $Rows = @(Get-CIPPExoApplicationAccessPolicy -TenantFilter 'contoso.onmicrosoft.com')

        $Rows.appId | Should -Be @('app-1', 'app-2', 'app-3')
        $Rows.id | Should -Be @('contoso\pol-1|app-1', 'contoso\pol-1|app-2', 'contoso\pol-2|app-3')
        $Rows[0].accessRight | Should -BeExactly 'DenyAccess'
        $Rows[2].scopeName | Should -BeExactly 'Sales'
        $Rows[2].isValid | Should -BeFalse
        Should -Invoke New-ExoRequest -Times 1 -Exactly -ParameterFilter { $cmdlet -eq 'Get-ApplicationAccessPolicy' }
    }
}

Describe 'Set-CIPPDBCacheExoApplicationAccessPolicies' {
    BeforeEach {
        Mock Write-LogMessage { }
        Mock Add-CIPPDbItem { }
    }

    It 'caches the policies' {
        Mock New-ExoRequest { [pscustomobject]@{ Identity = 'contoso\pol-1'; AppId = 'app-1'; AccessRight = 'RestrictAccess'; ScopeName = 'Sales'; IsValid = $true } }

        Set-CIPPDBCacheExoApplicationAccessPolicies -TenantFilter 'contoso.onmicrosoft.com'

        Should -Invoke Add-CIPPDbItem -Times 1 -Exactly -ParameterFilter { $Type -eq 'ExoApplicationAccessPolicies' -and @($Data).Count -eq 1 -and -not $ClearOnEmpty }
    }

    It 'records an empty set when there is no policy' {
        Mock New-ExoRequest { }

        Set-CIPPDBCacheExoApplicationAccessPolicies -TenantFilter 'contoso.onmicrosoft.com'

        Should -Invoke Add-CIPPDbItem -Times 1 -Exactly -ParameterFilter { $ClearOnEmpty -and @($Data).Count -eq 0 }
    }

    It 'writes nothing and rethrows when Exchange cannot be read' {
        Mock New-ExoRequest { throw 'Forbidden' }

        { Set-CIPPDBCacheExoApplicationAccessPolicies -TenantFilter 'contoso.onmicrosoft.com' } | Should -Throw '*Forbidden*'
        Should -Invoke Add-CIPPDbItem -Times 0
    }
}
