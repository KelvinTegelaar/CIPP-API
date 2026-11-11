BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))

    function Test-CIPPStandardLicense { param($StandardName, $TenantFilter, $Preset, $RequiredCapabilities, [switch]$SkipLog) }
    function New-GraphGetRequest { param($uri, $tenantid, $AsApp) }
    function Add-CIPPDbItem { param($TenantFilter, $Type, $Data, [switch]$AddCount, [switch]$ClearOnEmpty) }
    function Write-LogMessage { param($API, $tenant, $message, $sev, $LogData) }
    function Get-CippException { param($Exception) }

    . (Join-Path $RepoRoot 'Modules/CIPPDB/Public/DBCache/Set-CIPPDBCacheNetworkAccess.ps1')
    . (Join-Path $RepoRoot 'Modules/CIPPCore/Public/ConvertFrom-CIPPGSAForwardingRule.ps1')

    $script:Tenant = 'contoso.onmicrosoft.com'
}

Describe 'Set-CIPPDBCacheNetworkAccess' {
    BeforeEach {
        Mock Test-CIPPStandardLicense { $true }
        Mock Write-LogMessage {}
        Mock Add-CIPPDbItem {}
        Mock New-GraphGetRequest { [pscustomobject]@{ onboardingStatus = 'onboarded' } } -ParameterFilter { $uri -like '*/tenantStatus' }
        Mock New-GraphGetRequest { [pscustomobject]@{ signalingStatus = 'enabled' } } -ParameterFilter { $uri -like '*/settings/conditionalAccess' }
        Mock New-GraphGetRequest { [pscustomobject]@{ appRoleAssignmentRequired = $true } } -ParameterFilter { $uri -like '*/servicePrincipals/*' }
        Mock New-GraphGetRequest { [pscustomobject]@{ id = 'assignment-1'; principalId = 'g-1'; principalType = 'Group'; principalDisplayName = 'GSA users'; resourceId = 'sp-1' } } -ParameterFilter { $uri -like '*/servicePrincipals/sp-1/appRoleAssignedTo*' }
        Mock New-GraphGetRequest { [pscustomobject]@{ state = 'enabled'; configuration = [pscustomobject]@{ '@odata.type' = '#microsoft.graph.networkaccess.markdownBlockMessageConfiguration'; body = 'Blocked by IT' } } } -ParameterFilter { $uri -like '*/settings/customBlockPage' }
        Mock New-GraphGetRequest {
            [pscustomobject]@{
                id = 'm365-id'; name = 'Microsoft 365 traffic forwarding profile'; state = 'enabled'; trafficForwardingType = 'm365'; isCustomProfile = $false
                servicePrincipal = [pscustomobject]@{ id = 'sp-1' }; assignmentRules = $null
                policies = @([pscustomobject]@{ id = 'link-1'; state = 'disabled'; policy = [pscustomobject]@{ name = 'Exchange Online' } })
            }
        } -ParameterFilter { $uri -like '*/forwardingProfiles*' }
        Mock New-GraphGetRequest {
            @(
                [pscustomobject]@{ id = 'internet-id'; name = 'Internet traffic forwarding profile'; state = 'enabled'; trafficForwardingType = 'internet'; isCustomProfile = $false; servicePrincipal = [pscustomobject]@{ id = 'sp-2' }
                    policies = @(
                        [pscustomobject]@{ id = 'link-bypass'; state = 'enabled'; policy = [pscustomobject]@{ id = 'pol-bypass'; name = 'Custom bypass' } }
                        [pscustomobject]@{ id = 'link-default'; state = 'enabled'; policy = [pscustomobject]@{ id = 'pol-default'; name = 'Default Acquire' } }
                    )
                }
            )
        } -ParameterFilter { $uri -like '*/forwardingProfiles*' -and $script:WithInternet }
        Mock New-GraphGetRequest { @([pscustomobject]@{ id = 'r-1'; protocol = 'tcp'; ports = @('443'); destinations = @([pscustomobject]@{ value = 'a.contoso.com' }) }) } -ParameterFilter { $uri -like '*/forwardingPolicies/pol-bypass/policyRules' }
        Mock New-GraphGetRequest { @([pscustomobject]@{ id = 'rn-1'; name = 'Branch Sydney'; region = 'australiaEast'; forwardingProfiles = @([pscustomobject]@{ id = 'm365-id' }); deviceLinks = @([pscustomobject]@{ tunnelConfiguration = [pscustomobject]@{ preSharedKey = 'secret' } }) }) } -ParameterFilter { $uri -like '*/connectivity/remoteNetworks*' }
        $script:WithInternet = $false
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

    It 'caches who each profile''s app is assigned to, which is where the portal assigns a profile' {
        Set-CIPPDBCacheNetworkAccess -TenantFilter $script:Tenant
        Should -Invoke Add-CIPPDbItem -Times 1 -ParameterFilter {
            $Profile = @($Data)[0].profiles[0]
            $Profile.servicePrincipalId -eq 'sp-1' -and $Profile.appRoleAssignmentRequired -eq $true -and @($Profile.appRoleAssignedTo).Count -eq 1 -and
            $Profile.appRoleAssignedTo[0].principalId -eq 'g-1' -and $Profile.appRoleAssignedTo[0].principalType -eq 'Group' -and
            $Profile.PSObject.Properties.Name -notcontains 'assignmentRules'
        }
    }

    It 'leaves the assignment unknown when the profile''s app cannot be read' {
        Mock New-GraphGetRequest { throw 'Forbidden' } -ParameterFilter { $uri -like '*/servicePrincipals/*' }
        Set-CIPPDBCacheNetworkAccess -TenantFilter $script:Tenant
        Should -Invoke Add-CIPPDbItem -Times 1 -ParameterFilter { $null -eq @($Data)[0].profiles[0].appRoleAssignmentRequired -and @($Data)[0].profiles[0].id -eq 'm365-id' }
    }

    It 'caches the Internet profile''s custom rules with their ids, and reads no other policy''s rules' {
        $script:WithInternet = $true
        Set-CIPPDBCacheNetworkAccess -TenantFilter $script:Tenant
        Should -Invoke New-GraphGetRequest -Times 1 -Exactly -ParameterFilter { $uri -like '*/policyRules' }
        Should -Invoke Add-CIPPDbItem -Times 1 -ParameterFilter {
            $Bypass = @($Data)[0].profiles[0].policies[0]
            $Bypass.policyId -eq 'pol-bypass' -and $Bypass.rulesRead -and @($Bypass.ruleIds) -join ',' -eq 'r-1' -and
            $Bypass.rules[0].destination -eq 'a.contoso.com' -and $Bypass.rules[0].ports -eq '443' -and -not @($Data)[0].profiles[0].policies[1].rulesRead
        }
    }

    It 'caches remote networks with their profiles and never their tunnel settings' {
        Set-CIPPDBCacheNetworkAccess -TenantFilter $script:Tenant
        Should -Invoke New-GraphGetRequest -ParameterFilter { $uri -like '*/remoteNetworks*' -and $uri -notlike '*deviceLinks*' }
        Should -Invoke Add-CIPPDbItem -Times 1 -ParameterFilter {
            $Network = @($Data)[0].remoteNetworks[0]
            @($Data)[0].remoteNetworksRead -and $Network.name -eq 'Branch Sydney' -and @($Network.forwardingProfileIds) -join ',' -eq 'm365-id' -and
            $Network.PSObject.Properties.Name -notcontains 'deviceLinks' -and (ConvertTo-Json -Depth 10 -InputObject $Data) -notmatch 'secret'
        }
    }

    It 'marks the remote networks unread when they cannot be read' {
        Mock New-GraphGetRequest { throw 'Forbidden' } -ParameterFilter { $uri -like '*/connectivity/remoteNetworks*' }
        Set-CIPPDBCacheNetworkAccess -TenantFilter $script:Tenant
        Should -Invoke Add-CIPPDbItem -Times 1 -ParameterFilter { -not @($Data)[0].remoteNetworksRead -and @($Data)[0].signalingStatus -eq 'enabled' }
    }
}
