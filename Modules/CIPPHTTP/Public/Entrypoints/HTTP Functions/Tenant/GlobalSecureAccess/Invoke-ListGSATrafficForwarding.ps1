function Invoke-ListGSATrafficForwarding {
    <#
    .SYNOPSIS
        Lists a tenant's Global Secure Access traffic forwarding profiles
    .DESCRIPTION
        Returns the Microsoft 365, Internet Access and Private Access traffic forwarding profiles, read
        live, with who each profile is assigned to, its policy groups, the remote networks that use it and,
        for the Internet profile, the custom bypass and acquire destinations. Like the portal, each profile
        also carries the Conditional Access policies that target it and a warning when the tenant lacks the
        license the profile needs. A part that could not be read is null and named in readErrors.
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        Tenant.GlobalSecureAccess.Read
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $TenantFilter = $Request.Query.tenantFilter
    $Graph = 'https://graph.microsoft.com/beta'
    try {
        if ((New-GraphGetRequest -uri "$Graph/networkAccess/tenantStatus" -tenantid $TenantFilter -AsApp $true).onboardingStatus -ne 'onboarded') {
            throw [System.ArgumentException]::new('This tenant is not onboarded to Global Secure Access')
        }
        $RemoteNetworks = $null
        $RemoteNetworksError = $null
        try {
            $RemoteNetworks = @(New-GraphGetRequest -uri "$Graph/networkAccess/connectivity/remoteNetworks?`$expand=forwardingProfiles(`$select=id)" -tenantid $TenantFilter -AsApp $true)
        } catch {
            $RemoteNetworksError = "remote networks: $(Get-NormalizedError -Message $_.Exception.Message)"
        }
        $CaPolicies = $null
        $CaError = $null
        try {
            $CaPolicies = @(New-GraphGetRequest -uri "$Graph/identity/conditionalAccess/policies?`$select=id,displayName,state,conditions" -tenantid $TenantFilter -AsApp $true).Where({ $_.id })
        } catch {
            $CaError = "Conditional Access policies: $(Get-NormalizedError -Message $_.Exception.Message)"
        }
        $Capabilities = $(try { Get-CIPPTenantCapabilities -TenantFilter $TenantFilter } catch { $null })
        $Licenses = @{
            m365     = @{ Plans = @('AAD_PREMIUM', 'AAD_PREMIUM_P2'); Name = 'Microsoft Entra ID P1' }
            internet = @{ Plans = @('Entra_Premium_Internet_Access'); Name = 'Microsoft Entra Internet Access' }
            private  = @{ Plans = @('Entra_Premium_Private_Access'); Name = 'Microsoft Entra Private Access' }
        }

        $Body = @(foreach ($TrafficProfile in @(New-GraphGetRequest -uri "$Graph/networkAccess/forwardingProfiles?`$expand=policies(`$expand=policy)" -tenantid $TenantFilter -AsApp $true).Where({ $_.id -and -not $_.isCustomProfile })) {
                $ReadErrors = [System.Collections.Generic.List[string]]::new()
                if ($RemoteNetworksError) { $ReadErrors.Add($RemoteNetworksError) }
                if ($CaError) { $ReadErrors.Add($CaError) }
                $SpId = $TrafficProfile.servicePrincipal.id
                $AppId = "$($TrafficProfile.servicePrincipal.appId)"
                $Type = $TrafficProfile.trafficForwardingType
                $License = $Licenses[$Type]
                # Private Access is targeted through its apps, so only an explicit pick of the profile's app links it
                $LinkedPolicies = if ($null -ne $CaPolicies) {
                    , @($CaPolicies.Where({
                                $Include = @($_.conditions.applications.includeApplications)
                                ($Include -contains $AppId -or ($Type -ne 'private' -and $Include -contains 'All')) -and @($_.conditions.applications.excludeApplications) -notcontains $AppId
                            }).ForEach({ [pscustomobject]@{ id = $_.id; displayName = $_.displayName; state = $_.state } }))
                }
                $AllUsers = $null
                $Assignees = $null
                try {
                    $AllUsers = (New-GraphGetRequest -uri "$Graph/servicePrincipals/$($SpId)?`$select=appRoleAssignmentRequired" -tenantid $TenantFilter -AsApp $true).appRoleAssignmentRequired -eq $false
                    $Assignees = @(@(New-GraphGetRequest -uri "$Graph/servicePrincipals/$SpId/appRoleAssignedTo?`$select=id,principalId,principalType,principalDisplayName" -tenantid $TenantFilter -AsApp $true).Where({ $_.principalId }).ForEach({
                                [pscustomobject]@{ id = $_.id; principalId = $_.principalId; principalType = $_.principalType; principalDisplayName = $_.principalDisplayName }
                            }))
                } catch {
                    $AllUsers = $null
                    $ReadErrors.Add("assignment: $(Get-NormalizedError -Message $_.Exception.Message)")
                }
                $Row = [ordered]@{
                    id                    = $TrafficProfile.id
                    name                  = $TrafficProfile.name
                    trafficForwardingType = $TrafficProfile.trafficForwardingType
                    state                 = $TrafficProfile.state
                    servicePrincipalId    = $SpId
                    assignedToAllUsers    = $AllUsers
                    assignment            = if ($null -eq $AllUsers) { 'Unknown' } elseif ($AllUsers) { 'All users' } elseif ($Assignees.Count) { "$($Assignees.Count) users and groups" } else { 'Not assigned' }
                    assignees             = $Assignees
                    policies              = @(@($TrafficProfile.policies).Where({ $_ }).ForEach({ [pscustomobject]@{ id = $_.id; policyId = $_.policy.id; policyName = $_.policy.name; state = $_.state } }))
                    remoteNetworks        = if ($null -ne $RemoteNetworks) { , @($RemoteNetworks.Where({ @($_.forwardingProfiles).id -contains $TrafficProfile.id }).ForEach({ [pscustomobject]@{ id = $_.id; name = $_.name } })) }
                    linkedConditionalAccessPolicies = $LinkedPolicies
                    licenseWarning        = if ($Capabilities -and $License -and @($License.Plans.Where({ $Capabilities.$_ -eq $true })).Count -eq 0) { "The tenant is missing the license needed to use this profile ($($License.Name))." }
                }
                if ($TrafficProfile.trafficForwardingType -eq 'internet') {
                    foreach ($Kind in @(@{ Key = 'customBypass'; Policy = 'Custom bypass' }, @{ Key = 'customAcquire'; Policy = 'Custom Acquire' })) {
                        $Row[$Kind.Key] = $null
                        $PolicyId = @($TrafficProfile.policies).Where({ $_.policy.name -eq $Kind.Policy }, 'First')[0].policy.id
                        try {
                            if (-not $PolicyId) { throw "the profile has no $($Kind.Policy) policy" }
                            $Row[$Kind.Key] = @(ConvertFrom-CIPPGSAForwardingRule -Rules (@(New-GraphGetRequest -uri "$Graph/networkAccess/forwardingPolicies/$PolicyId/policyRules" -tenantid $TenantFilter -AsApp $true).Where({ $_.id })))
                        } catch {
                            $ReadErrors.Add("$($Kind.Policy) rules: $(Get-NormalizedError -Message $_.Exception.Message)")
                        }
                    }
                }
                $Row.readErrors = @($ReadErrors)
                [pscustomobject]$Row
            })
        $StatusCode = [HttpStatusCode]::OK
    } catch {
        $Body = @{ Results = "Failed to list traffic forwarding profiles: $(Get-NormalizedError -Message $_.Exception.Message)" }
        $StatusCode = Get-CippErrorStatusCode -ErrorRecord $_
    }

    return ([HttpResponseContext]@{ StatusCode = $StatusCode; Body = $Body })
}
