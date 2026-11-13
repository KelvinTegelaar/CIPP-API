function Get-CIPPBaselineGlobalSecureAccessTrafficProfileState {
    <#
    .SYNOPSIS
        Prepare hook for the Global Secure Access traffic forwarding profile standards.
    .DESCRIPTION
        Shared by the Microsoft 365 profile and Internet Access standards, which manage the m365 and
        internet profiles. Grades the profile state from the NetworkAccess cache and, when the profile
        should be enabled, its disabled policy links and its assignment. A profile is assigned through
        its app, as the portal does: assignment not required means all users, otherwise the app's
        appRoleAssignedTo. Configured groups are added to whatever is assigned already (wildcards
        allowed, resolved from the Groups cache), and Do not assign leaves the assignment alone, so
        assignments made by hand are never removed.

        Configured remote networks (names, wildcards allowed) get the profile added to the profiles
        they already use; none is ever removed.

        Only the writes that are needed are carried on Current for GraphBulkSweep: stateWrites,
        linkWrites, assignmentWrites (one app role assignment per group), requirementWrites and
        remoteNetworkWrites (the remote network's whole profile list, which Graph replaces).
    .FUNCTIONALITY
        Internal
    #>
    [CmdletBinding()]
    param($Item, $TenantFilter)

    $TrafficType = if ($Item.BaseName -eq 'GlobalSecureAccessInternetAccess') { 'internet' } else { 'm365' }
    $Variables = $Item.Variables
    $ProfileState = "$($Variables.profileState.value ?? $Variables.profileState)"
    if (-not $ProfileState) { $ProfileState = 'enabled' }
    $AssignTo = "$($Variables.assignTo.value ?? $Variables.assignTo)"
    if (-not $AssignTo) { $AssignTo = 'AllDevicesAndUsers' }
    $GroupRefs = @("$($Variables.customGroup)" -split ',').ForEach({ $_.Trim() }).Where({ $_ })
    if ($ProfileState -eq 'enabled' -and $AssignTo -eq 'customGroup' -and $GroupRefs.Count -eq 0) {
        return @{ Current = $null; ConfigError = $true; NoDataReason = 'Assign to Custom Group is selected but no group name is configured' }
    }

    $Row = @(New-CIPPDbRequest -TenantFilter $TenantFilter -Type 'NetworkAccess').Where({ $_ }, 'First')[0]
    if (-not $Row) { return @{ Current = $null; NoDataReason = 'the NetworkAccess cache has no data for this tenant' } }
    if (-not $Row.onboarded) { return @{ Current = $null; NoDataReason = 'the tenant is not onboarded to Global Secure Access; the Set up Global Secure Access standard onboards it' } }
    $TrafficProfile = @($Row.profiles).Where({ $_.trafficForwardingType -eq $TrafficType -and -not $_.isCustomProfile }, 'First')[0]
    if (-not $TrafficProfile) { return @{ Current = $null; NoDataReason = "the $TrafficType traffic forwarding profile was not found" } }

    $Expected = [ordered]@{ state = $ProfileState }
    $Current = [ordered]@{ state = "$($TrafficProfile.state)" }
    $StateWrites = @(if ($TrafficProfile.state -ne $ProfileState) { [pscustomobject]@{ id = $TrafficProfile.id; state = $ProfileState } })
    $LinkWrites = @()
    $AssignmentWrites = @()
    $RequirementWrites = @()

    if ($ProfileState -eq 'enabled') {
        $DisabledLinks = @($TrafficProfile.policies).Where({ $_ -and $_.state -ne 'enabled' })
        $Expected.disabledPolicies = @()
        $Current.disabledPolicies = @($DisabledLinks.ForEach({ "$($_.policyName)" }) | Sort-Object)
        $LinkWrites = @($DisabledLinks.ForEach({ [pscustomobject]@{ profileId = $TrafficProfile.id; id = $_.id } }))

        $Required = $TrafficProfile.appRoleAssignmentRequired
        if ($AssignTo -ne 'DoNotAssign' -and ($null -eq $Required -or -not $TrafficProfile.servicePrincipalId)) {
            return @{ Current = $null; NoDataReason = "could not read who the $TrafficType traffic forwarding profile is assigned to" }
        }
        $Assignees = @(@($TrafficProfile.appRoleAssignedTo).Where({ $_.principalId }))
        $AssignedGroups = @($Assignees.Where({ $_.principalType -eq 'Group' }).ForEach({ "$($_.principalId)" }))
        $CurrentAssignment = if ($Required -eq $false) { 'All users' } elseif ($Assignees.Count -gt 0) { 'Specific users and groups' } else { 'Not assigned' }

        switch ($AssignTo) {
            'AllDevicesAndUsers' {
                $Expected.assignment = 'All users'
                $Current.assignment = $CurrentAssignment
                if ($Required -ne $false) {
                    $RequirementWrites = @([pscustomobject]@{ servicePrincipalId = $TrafficProfile.servicePrincipalId; required = $false })
                }
            }
            'DoNotAssign' {}
            default {
                $Groups = @(Get-CIPPBaselineCacheRows -TenantFilter $TenantFilter -Type 'Groups')
                $Missing = [System.Collections.Generic.List[string]]::new()
                $Resolved = [System.Collections.Generic.List[string]]::new()
                foreach ($Ref in $GroupRefs) {
                    $Pattern = $Ref -replace '\[', '`[' -replace '\]', '`]'
                    $Matched = @($Groups.Where({ $_.displayName -like $Pattern }))
                    if ($Matched.Count -eq 0) { $Missing.Add($Ref); continue }
                    foreach ($Group in $Matched) {
                        $Resolved.Add("$($Group.id)")
                        if ($AssignedGroups -notcontains "$($Group.id)") { $Missing.Add("$($Group.displayName)") }
                    }
                }
                $Expected.assignment = 'Specific users and groups'
                $Current.assignment = $CurrentAssignment
                $Expected.missingGroups = @()
                $Current.missingGroups = @($Missing | Sort-Object -Unique)
                $NewGroups = @($Resolved.Where({ $AssignedGroups -notcontains $_ }) | Sort-Object -Unique)
                $AssignmentWrites = @($NewGroups.ForEach({ [pscustomobject]@{ servicePrincipalId = $TrafficProfile.servicePrincipalId; principalId = $_ } }))
                if ($Required -eq $false -and $Resolved.Count -gt 0) {
                    $RequirementWrites = @([pscustomobject]@{ servicePrincipalId = $TrafficProfile.servicePrincipalId; required = $true })
                }
            }
        }
    }

    $RemoteNetworkWrites = @()
    $NetworkRefs = @(@($Variables.remoteNetworks).ForEach({ "$($_.value ?? $_)" -split ',' }).ForEach({ $_.Trim() }).Where({ $_ }))
    # Graph only assigns an enabled profile to a remote network.
    if ($NetworkRefs.Count -gt 0 -and $ProfileState -eq 'enabled') {
        if ($Row.remoteNetworksRead -ne $true) { return @{ Current = $null; NoDataReason = 'could not read the tenant''s remote networks' } }
        $MissingNetworks = [System.Collections.Generic.List[string]]::new()
        $Writes = [ordered]@{}
        foreach ($Ref in $NetworkRefs) {
            $Pattern = $Ref -replace '\[', '`[' -replace '\]', '`]'
            $Matched = @(@($Row.remoteNetworks).Where({ $_.name -like $Pattern }))
            if ($Matched.Count -eq 0) { $MissingNetworks.Add($Ref); continue }
            foreach ($Network in $Matched.Where({ @($_.forwardingProfileIds) -notcontains $TrafficProfile.id })) {
                $MissingNetworks.Add("$($Network.name)")
                $Writes["$($Network.id)"] = [pscustomobject]@{
                    remoteNetworkId = $Network.id
                    profiles        = @(@(@($Network.forwardingProfileIds) + $TrafficProfile.id).ForEach({ [ordered]@{ '@odata.type' = '#microsoft.graph.networkaccess.forwardingProfile'; id = $_ } }))
                }
            }
        }
        $Expected.missingRemoteNetworks = @()
        $Current.missingRemoteNetworks = @($MissingNetworks | Sort-Object -Unique)
        $RemoteNetworkWrites = @($Writes.Values)
    }

    $CurrentObject = [pscustomobject]$Current
    $CurrentObject | Add-Member -NotePropertyName 'stateWrites' -NotePropertyValue $StateWrites
    $CurrentObject | Add-Member -NotePropertyName 'linkWrites' -NotePropertyValue $LinkWrites
    $CurrentObject | Add-Member -NotePropertyName 'assignmentWrites' -NotePropertyValue $AssignmentWrites
    $CurrentObject | Add-Member -NotePropertyName 'requirementWrites' -NotePropertyValue $RequirementWrites
    $CurrentObject | Add-Member -NotePropertyName 'remoteNetworkWrites' -NotePropertyValue $RemoteNetworkWrites
    @{ Expected = [pscustomobject]$Expected; Current = $CurrentObject }
}
