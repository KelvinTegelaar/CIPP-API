BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))

    function Test-CIPPStandardLicense { param($StandardName, $TenantFilter, $Preset, $RequiredCapabilities, [switch]$SkipLog) }
    function New-GraphGetRequest { param($uri, $tenantid, $AsApp) }
    function Add-CIPPDbItem { param($TenantFilter, $Type, $Data, [switch]$AddCount, [switch]$ClearOnEmpty) }
    function Write-LogMessage { param($API, $tenant, $message, $sev, $LogData) }
    function Get-CippException { param($Exception) }

    . (Join-Path $RepoRoot 'Modules/CIPPDB/Public/DBCache/Set-CIPPDBCacheNetworkAccess.ps1')

    $script:Tenant = 'contoso.onmicrosoft.com'
    $script:Rules = [pscustomobject]@{ devicePropertyFilters = [pscustomobject]@{ platforms = 'windows,macOS' }; assignments = [pscustomobject]@{ '@odata.type' = '#microsoft.graph.networkaccess.forwardingProfileAssignmentsAllMembership' } }
}

Describe 'Set-CIPPDBCacheNetworkAccess' {
    BeforeEach {
        Mock Test-CIPPStandardLicense { $true }
        Mock Write-LogMessage {}
        Mock Add-CIPPDbItem {}
        Mock New-GraphGetRequest { [pscustomobject]@{ onboardingStatus = 'onboarded' } } -ParameterFilter { $uri -like '*/tenantStatus' }
        Mock New-GraphGetRequest { [pscustomobject]@{ signalingStatus = 'enabled' } } -ParameterFilter { $uri -like '*/settings/conditionalAccess' }
        Mock New-GraphGetRequest { [pscustomobject]@{ appRoleAssignmentRequired = $false } } -ParameterFilter { $uri -like '*/servicePrincipals/*' }
        Mock New-GraphGetRequest { [pscustomobject]@{ state = 'enabled'; configuration = [pscustomobject]@{ '@odata.type' = '#microsoft.graph.networkaccess.markdownBlockMessageConfiguration'; body = 'Blocked by IT' } } } -ParameterFilter { $uri -like '*/settings/customBlockPage' }
        Mock New-GraphGetRequest {
            [pscustomobject]@{
                id = 'm365-id'; name = 'Microsoft 365 traffic forwarding profile'; state = 'enabled'; trafficForwardingType = 'm365'; isCustomProfile = $false
                servicePrincipal = [pscustomobject]@{ id = 'sp-1' }; assignmentRules = $script:Rules
                policies = @([pscustomobject]@{ id = 'link-1'; state = 'disabled'; policy = [pscustomobject]@{ name = 'Exchange Online' } })
            }
        } -ParameterFilter { $uri -like '*/forwardingProfiles*' }
    }

    It 'writes an empty set for a tenant without Entra ID P1' {
        Mock Test-CIPPStandardLicense { $false }
        Set-CIPPDBCacheNetworkAccess -TenantFilter $script:Tenant
        Should -Invoke Add-CIPPDbItem -Times 1 -ParameterFilter { $Type -eq 'NetworkAccess' -and @($Data).Count -eq 0 }
        Should -Invoke New-GraphGetRequest -Times 0
    }

    It 'caches one row with onboarding, signalling and each profile with its links' {
        Set-CIPPDBCacheNetworkAccess -TenantFilter $script:Tenant
        Should -Invoke Add-CIPPDbItem -Times 1 -ParameterFilter {
            $Row = @($Data)[0]
            $Type -eq 'NetworkAccess' -and $Row.onboardingStatus -eq 'onboarded' -and $Row.onboarded -and $Row.signalingStatus -eq 'enabled' -and
            $Row.profiles[0].id -eq 'm365-id' -and $Row.profiles[0].trafficForwardingType -eq 'm365' -and
            $Row.profiles[0].policies[0].id -eq 'link-1' -and $Row.profiles[0].policies[0].state -eq 'disabled' -and $Row.profiles[0].policies[0].policyName -eq 'Exchange Online'
        }
    }

    It 'reads no profiles or signalling before the tenant is onboarded' {
        Mock New-GraphGetRequest { [pscustomobject]@{ onboardingStatus = 'offboarded' } } -ParameterFilter { $uri -like '*/tenantStatus' }
        Set-CIPPDBCacheNetworkAccess -TenantFilter $script:Tenant
        Should -Invoke New-GraphGetRequest -Times 1 -Exactly
        Should -Invoke Add-CIPPDbItem -Times 1 -ParameterFilter { -not @($Data)[0].onboarded -and @(@($Data)[0].profiles).Count -eq 0 }
    }

    It 'caches the custom block page state and message' {
        Set-CIPPDBCacheNetworkAccess -TenantFilter $script:Tenant
        Should -Invoke Add-CIPPDbItem -Times 1 -ParameterFilter { @($Data)[0].customBlockPage.state -eq 'enabled' -and @($Data)[0].customBlockPage.message -eq 'Blocked by IT' }
    }

    It 'still caches the rest when the block page cannot be read' {
        Mock New-GraphGetRequest { throw 'Forbidden' } -ParameterFilter { $uri -like '*/settings/customBlockPage' }
        Set-CIPPDBCacheNetworkAccess -TenantFilter $script:Tenant
        Should -Invoke Add-CIPPDbItem -Times 1 -ParameterFilter { @($Data)[0].signalingStatus -eq 'enabled' -and $null -eq @($Data)[0].customBlockPage }
    }

    It 'caches each profile''s assignment rules' {
        Set-CIPPDBCacheNetworkAccess -TenantFilter $script:Tenant
        Should -Invoke Add-CIPPDbItem -Times 1 -ParameterFilter {
            $Rules = @($Data)[0].profiles[0].assignmentRules
            $Rules.assignments.'@odata.type' -like '*AllMembership' -and $Rules.devicePropertyFilters.platforms -eq 'windows,macOS'
        }
    }
}
