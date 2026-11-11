BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))

    function Test-CIPPStandardLicense { param($StandardName, $TenantFilter, $Preset, [switch]$SkipLog) }
    function New-GraphGetRequest { param($uri, $tenantid, $AsApp) }
    function Add-CIPPDbItem { param($TenantFilter, $Type, $Data, [switch]$AddCount, [switch]$ClearOnEmpty) }
    function Write-LogMessage { param($API, $tenant, $message, $sev, $LogData) }
    function Get-CippException { param($Exception) }

    . (Join-Path $RepoRoot 'Modules/CIPPDB/Public/DBCache/Set-CIPPDBCacheNetworkAccessFiltering.ps1')

    $script:Tenant = 'contoso.onmicrosoft.com'
}

Describe 'Set-CIPPDBCacheNetworkAccessFiltering' {
    BeforeEach {
        Mock Test-CIPPStandardLicense { $true }
        Mock Write-LogMessage {}
        Mock Add-CIPPDbItem {}
    }

    It 'clears the cache without calling Graph when the tenant is unlicensed' {
        Mock Test-CIPPStandardLicense { $false }
        Mock New-GraphGetRequest {}

        Set-CIPPDBCacheNetworkAccessFiltering -TenantFilter $script:Tenant

        Should -Invoke New-GraphGetRequest -Times 0
        Should -Invoke Add-CIPPDbItem -Times 1 -ParameterFilter { $Type -eq 'NetworkAccessFiltering' -and @($Data).Count -eq 0 -and $ClearOnEmpty }
    }

    It 'writes an empty set and reads nothing else when the tenant is not onboarded' {
        Mock New-GraphGetRequest { [pscustomobject]@{ onboardingStatus = 'offboarded' } } -ParameterFilter { $uri -like '*/tenantStatus' }
        Mock New-GraphGetRequest { throw 'should not be called' }

        Set-CIPPDBCacheNetworkAccessFiltering -TenantFilter $script:Tenant

        Should -Invoke New-GraphGetRequest -Times 1 -Exactly
        Should -Invoke Add-CIPPDbItem -Times 1 -ParameterFilter { @($Data).Count -eq 0 }
    }

    It 'writes profiles and policies tagged with their kind, app-only' {
        Mock New-GraphGetRequest { [pscustomobject]@{ onboardingStatus = 'onboarded' } } -ParameterFilter { $uri -like '*/tenantStatus' }
        Mock New-GraphGetRequest {
            [pscustomobject]@{ id = 'p1'; name = 'Staff'; priority = 1000; policies = @([pscustomobject]@{ priority = 100; policy = [pscustomobject]@{ id = 'f1'; name = 'Block' } }); conditionalAccessPolicies = @() }
        } -ParameterFilter { $uri -like '*/filteringProfiles?*expand=policies(*policy),conditionalAccessPolicies' }
        Mock New-GraphGetRequest {
            [pscustomobject]@{ id = 'f1'; name = 'Block'; action = 'block'; policyRules = @([pscustomobject]@{ name = 'r'; ruleType = 'webCategory' }) }
            [pscustomobject]@{ id = 'f2'; name = 'All websites'; action = 'allow'; policyRules = @() }
        } -ParameterFilter { $uri -like '*/filteringPolicies?*expand=policyRules' }

        Set-CIPPDBCacheNetworkAccessFiltering -TenantFilter $script:Tenant

        Should -Invoke New-GraphGetRequest -Times 3 -Exactly -ParameterFilter { $AsApp -eq $true }
        Should -Invoke Add-CIPPDbItem -Times 1 -ParameterFilter {
            $Rows = @($Data)
            $Rows.Count -eq 3 -and
            ($Rows | Where-Object kind -EQ 'profile').id -eq 'p1' -and
            (@($Rows | Where-Object kind -EQ 'policy').id -join ',') -eq 'f1,f2' -and
            ($Rows | Where-Object id -EQ 'p1').policies[0].policy.name -eq 'Block'
        }
    }

    It 'logs and rethrows a Graph failure instead of reporting success' {
        Mock New-GraphGetRequest { [pscustomobject]@{ onboardingStatus = 'onboarded' } } -ParameterFilter { $uri -like '*/tenantStatus' }
        Mock New-GraphGetRequest { throw 'Graph returned 500' }

        { Set-CIPPDBCacheNetworkAccessFiltering -TenantFilter $script:Tenant } | Should -Throw '*500*'
        Should -Invoke Add-CIPPDbItem -Times 0
        Should -Invoke Write-LogMessage -Times 1 -ParameterFilter { $sev -eq 'Error' }
    }
}
