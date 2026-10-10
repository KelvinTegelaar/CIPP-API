function Set-CIPPDBCacheNetworkAccess {
    <#
    .SYNOPSIS
        Caches Global Secure Access state for a tenant: onboarding status, forwarding
        profiles (with policy groups and the profile app's assignment flag) and the
        Conditional Access signaling setting. One row per tenant.

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

        # Every networkAccess path except tenantStatus answers 403 until the tenant is onboarded.
        if ($Onboarded) {
            foreach ($RawProfile in @(New-GraphGetRequest -uri 'https://graph.microsoft.com/beta/networkAccess/forwardingProfiles?$expand=policies($expand=policy)' -tenantid $TenantFilter -AsApp $true)) {
                $AssignmentRequired = $null
                if ($RawProfile.servicePrincipal.id) {
                    try {
                        $Sp = New-GraphGetRequest -uri "https://graph.microsoft.com/beta/servicePrincipals/$($RawProfile.servicePrincipal.id)?`$select=appRoleAssignmentRequired" -tenantid $TenantFilter -AsApp $true
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
                        appRoleAssignmentRequired = $AssignmentRequired
                        policies                  = @($RawProfile.policies | ForEach-Object { [PSCustomObject]@{ id = $_.id; state = $_.state; policyName = $_.policy.name } })
                    })
            }
            $SignalingStatus = (New-GraphGetRequest -uri 'https://graph.microsoft.com/beta/networkAccess/settings/conditionalAccess' -tenantid $TenantFilter -AsApp $true).signalingStatus
        }

        $Row = [PSCustomObject]@{
            id               = 'networkAccess'
            onboardingStatus = $Status.onboardingStatus
            onboarded        = $Onboarded
            signalingStatus  = $SignalingStatus
            profiles         = @($Profiles)
        }
        Add-CIPPDbItem -TenantFilter $TenantFilter -Type 'NetworkAccess' -Data @($Row) -AddCount -ClearOnEmpty
    } catch {
        Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message "Failed to cache Global Secure Access state: $($_.Exception.Message)" -sev Error -LogData (Get-CippException -Exception $_)
    }
}
