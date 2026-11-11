function Set-CIPPDBCacheNetworkAccess {
    <#
    .SYNOPSIS
        Caches Global Secure Access state for a tenant: onboarding status, forwarding
        profiles (with policy groups, the Internet profile's custom rules and who the profile's
        app is assigned to), remote networks with their profiles, and the Conditional Access
        signaling setting. One row per tenant.

    .PARAMETER TenantFilter
        The tenant to cache Global Secure Access state for

    .PARAMETER QueueId
        The queue ID to update with total tasks (optional)
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$TenantFilter,
        [string]$QueueId
    )

    try {
        $TestResult = Test-CIPPStandardLicense -StandardName 'NetworkAccessCache' -TenantFilter $TenantFilter -Preset Entra -SkipLog
        if ($TestResult -eq $false) {
            Add-CIPPDbItem -TenantFilter $TenantFilter -Type 'NetworkAccess' -Data @() -AddCount -ClearOnEmpty
            return
        }

        $Status = New-GraphGetRequest -uri 'https://graph.microsoft.com/beta/networkAccess/tenantStatus' -tenantid $TenantFilter -AsApp $true
        $Onboarded = $Status.onboardingStatus -eq 'onboarded'
        $Profiles = [System.Collections.Generic.List[object]]::new()
        $SignalingStatus = $null
        $CustomBlockPage = $null
        $RemoteNetworks = $null

        # Every networkAccess path except tenantStatus answers 403 until the tenant is onboarded.
        if ($Onboarded) {
            foreach ($RawProfile in @(New-GraphGetRequest -uri 'https://graph.microsoft.com/beta/networkAccess/forwardingProfiles?$expand=policies($expand=policy)' -tenantid $TenantFilter -AsApp $true)) {
                $AssignmentRequired = $null
                $AssignedTo = @()
                if ($RawProfile.servicePrincipal.id) {
                    try {
                        $Sp = New-GraphGetRequest -uri "https://graph.microsoft.com/beta/servicePrincipals/$($RawProfile.servicePrincipal.id)?`$select=appRoleAssignmentRequired" -tenantid $TenantFilter -AsApp $true
                        $AssignedTo = @(New-GraphGetRequest -uri "https://graph.microsoft.com/beta/servicePrincipals/$($RawProfile.servicePrincipal.id)/appRoleAssignedTo?`$select=principalId,principalType,principalDisplayName" -tenantid $TenantFilter -AsApp $true).ForEach({
                                [PSCustomObject]@{ principalId = $_.principalId; principalType = $_.principalType; principalDisplayName = $_.principalDisplayName }
                            })
                        $AssignmentRequired = [bool]$Sp.appRoleAssignmentRequired
                    } catch {
                        Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message "Could not read the app behind forwarding profile '$($RawProfile.name)': $($_.Exception.Message)" -sev Warning
                    }
                }
                $Profiles.Add([PSCustomObject]@{
                        id                        = $RawProfile.id
                        name                      = $RawProfile.name
                        state                     = $RawProfile.state
                        trafficForwardingType     = $RawProfile.trafficForwardingType
                        isCustomProfile           = [bool]$RawProfile.isCustomProfile
                        servicePrincipalId        = $RawProfile.servicePrincipal.id
                        # The portal assigns a profile through its app: not required = all users, else appRoleAssignedTo
                        appRoleAssignmentRequired = $AssignmentRequired
                        appRoleAssignedTo         = $AssignedTo
                        policies                  = @($RawProfile.policies | ForEach-Object {
                                $Link = $_
                                $Rules = $null
                                $RuleIds = $null
                                if ($RawProfile.trafficForwardingType -eq 'internet' -and $Link.policy.name -in 'Custom bypass', 'Custom Acquire') {
                                    try {
                                        $RawRules = @(New-GraphGetRequest -uri "https://graph.microsoft.com/beta/networkAccess/forwardingPolicies/$($Link.policy.id)/policyRules" -tenantid $TenantFilter -AsApp $true).Where({ $_.id })
                                        $Rules = @(ConvertFrom-CIPPGSAForwardingRule -Rules $RawRules)
                                        $RuleIds = @($RawRules.ForEach({ $_.id }))
                                    } catch {
                                        Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message "Could not read the rules of forwarding policy '$($Link.policy.name)': $($_.Exception.Message)" -sev Warning
                                    }
                                }
                                [PSCustomObject]@{ id = $Link.id; state = $Link.state; policyName = $Link.policy.name; policyId = $Link.policy.id; rulesRead = $null -ne $RuleIds; rules = $Rules; ruleIds = $RuleIds }
                            })
                    })
            }
            # Device links are never read: their tunnel configuration holds the VPN pre-shared key.
            try {
                $RemoteNetworks = @(New-GraphGetRequest -uri 'https://graph.microsoft.com/beta/networkAccess/connectivity/remoteNetworks?$expand=forwardingProfiles($select=id)' -tenantid $TenantFilter -AsApp $true).ForEach({
                        [PSCustomObject]@{ id = $_.id; name = $_.name; region = $_.region; forwardingProfileIds = @(@($_.forwardingProfiles).ForEach({ $_.id })) }
                    })
            } catch {
                $RemoteNetworks = $null
                Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message "Could not read Global Secure Access remote networks: $($_.Exception.Message)" -sev Warning
            }
            $SignalingStatus = (New-GraphGetRequest -uri 'https://graph.microsoft.com/beta/networkAccess/settings/conditionalAccess' -tenantid $TenantFilter -AsApp $true).signalingStatus
            try {
                $BlockPage = New-GraphGetRequest -uri 'https://graph.microsoft.com/beta/networkAccess/settings/customBlockPage' -tenantid $TenantFilter -AsApp $true
                $CustomBlockPage = [PSCustomObject]@{ state = $BlockPage.state; message = $BlockPage.configuration.body }
            } catch {
                Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message "Could not read the Global Secure Access custom block page: $($_.Exception.Message)" -sev Warning
            }
        }

        $Row = [PSCustomObject]@{
            id               = 'networkAccess'
            onboardingStatus = $Status.onboardingStatus
            onboarded        = $Onboarded
            signalingStatus  = $SignalingStatus
            customBlockPage  = $CustomBlockPage
            profiles         = @($Profiles)
            remoteNetworksRead = $null -ne $RemoteNetworks
            remoteNetworks     = @($RemoteNetworks)
        }
        Add-CIPPDbItem -TenantFilter $TenantFilter -Type 'NetworkAccess' -Data @($Row) -AddCount -ClearOnEmpty
    } catch {
        Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message "Failed to cache Global Secure Access state: $($_.Exception.Message)" -sev Error -LogData (Get-CippException -Exception $_)
    }
}
