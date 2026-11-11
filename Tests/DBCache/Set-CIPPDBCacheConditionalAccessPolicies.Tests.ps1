BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))

    function Test-CIPPStandardLicense { param($StandardName, $TenantFilter, $Preset, [switch]$SkipLog) }
    function New-GraphGetRequest { param($uri, $tenantid, $AsApp) }
    function Add-CIPPDbItem { param($TenantFilter, $Type, $Data, [switch]$AddCount, [switch]$ClearOnEmpty) }
    function Set-CIPPDBCacheNetworkAccessFiltering { param($TenantFilter) }
    function Write-LogMessage { param($API, $tenant, $message, $sev, $LogData) }
    function Get-CippException { param($Exception) }

    . (Join-Path $RepoRoot 'Modules/CIPPDB/Public/DBCache/Set-CIPPDBCacheConditionalAccessPolicies.ps1')

    $script:Tenant = 'contoso.onmicrosoft.com'
    $script:Policies = @()
}

Describe 'Set-CIPPDBCacheConditionalAccessPolicies' {
    BeforeEach {
        Mock Test-CIPPStandardLicense { $true }
        Mock Write-LogMessage {}
        Mock Add-CIPPDbItem {}
        Mock Set-CIPPDBCacheNetworkAccessFiltering {}
        Mock New-GraphGetRequest { $script:Policies } -ParameterFilter { $uri -like '*/conditionalAccess/policies*' }
        Mock New-GraphGetRequest { @() }
    }

    It 'writes empty CA, named location and authentication strength sets for an unlicensed tenant' {
        Mock Test-CIPPStandardLicense { $false }
        Set-CIPPDBCacheConditionalAccessPolicies -TenantFilter $script:Tenant
        Should -Invoke Add-CIPPDbItem -Times 1 -ParameterFilter { $Type -eq 'ConditionalAccessPolicies' -and @($Data).Count -eq 0 -and $ClearOnEmpty }
        Should -Invoke Add-CIPPDbItem -Times 1 -ParameterFilter { $Type -eq 'NamedLocations' -and @($Data).Count -eq 0 -and $ClearOnEmpty }
        Should -Invoke Add-CIPPDbItem -Times 1 -ParameterFilter { $Type -eq 'AuthenticationStrengths' -and @($Data).Count -eq 0 -and $ClearOnEmpty }
        Should -Invoke New-GraphGetRequest -Times 0
    }

    It 'caches the policies as an authoritative set' {
        $script:Policies = @([pscustomobject]@{ id = 'p1'; displayName = 'Require MFA' })
        Set-CIPPDBCacheConditionalAccessPolicies -TenantFilter $script:Tenant
        Should -Invoke Add-CIPPDbItem -Times 1 -ParameterFilter { $Type -eq 'ConditionalAccessPolicies' -and @($Data).Count -eq 1 -and $ClearOnEmpty }
    }

    It 'collects Global Secure Access filtering when a policy applies a security profile' {
        $script:Policies = @([pscustomobject]@{ id = 'p1'; displayName = 'Web filtering'; sessionControls = [pscustomobject]@{ globalSecureAccessFilteringProfile = [pscustomobject]@{ profileId = 'prof-1'; isEnabled = $true } } })
        Set-CIPPDBCacheConditionalAccessPolicies -TenantFilter $script:Tenant
        Should -Invoke Set-CIPPDBCacheNetworkAccessFiltering -Times 1 -ParameterFilter { $TenantFilter -eq $script:Tenant }
    }

    It 'still caches named locations and authentication strengths when that collection fails' {
        $script:Policies = @([pscustomobject]@{ id = 'p1'; displayName = 'Web filtering'; sessionControls = [pscustomobject]@{ globalSecureAccessFilteringProfile = [pscustomobject]@{ profileId = 'prof-1'; isEnabled = $true } } })
        Mock Set-CIPPDBCacheNetworkAccessFiltering { throw 'Graph said no' }
        Set-CIPPDBCacheConditionalAccessPolicies -TenantFilter $script:Tenant
        Should -Invoke Add-CIPPDbItem -Times 1 -ParameterFilter { $Type -eq 'NamedLocations' }
        Should -Invoke Add-CIPPDbItem -Times 1 -ParameterFilter { $Type -eq 'AuthenticationStrengths' }
        Should -Invoke Write-LogMessage -Times 1 -ParameterFilter { $message -like '*Global Secure Access filtering*Graph said no' }
    }

    It 'does not collect Global Secure Access filtering for policies without a security profile' {
        $script:Policies = @([pscustomobject]@{ id = 'p1'; displayName = 'Require MFA'; sessionControls = [pscustomobject]@{ signInFrequency = [pscustomobject]@{ value = 4 } } })
        Set-CIPPDBCacheConditionalAccessPolicies -TenantFilter $script:Tenant
        Should -Invoke Set-CIPPDBCacheNetworkAccessFiltering -Times 0
    }
}
