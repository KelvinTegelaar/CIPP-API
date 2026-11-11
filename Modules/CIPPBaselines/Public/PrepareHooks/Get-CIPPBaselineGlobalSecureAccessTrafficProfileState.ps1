function Get-CIPPBaselineGlobalSecureAccessTrafficProfileState {
    <#
    .SYNOPSIS
        Prepare hook for the Global Secure Access traffic forwarding profile standards.
    .DESCRIPTION
        Shared by the Microsoft 365 profile and Internet Access standards, which manage the m365 and
        internet profiles. Grades the profile state from the NetworkAccess cache and, when the profile
        should be enabled, its disabled policy links and its assignment. Assignment follows the Intune
        template convention: all users and devices, or configured groups (added to whatever is
        assigned already, wildcards allowed, resolved from the Groups cache). Do not assign leaves the
        assignment alone, so assignments made by hand are never removed. Assignment is managed only
        on tenants with a Global Secure Access licence (Internet Access or Private Access): Graph does
        not return a profile's assignment without one, so it is neither graded nor written there.

        Only the writes that are needed are carried on Current for GraphBulkSweep: stateWrites,
        linkWrites and assignmentWrites. The assignment body keeps the portal's property order
        (devicePropertyFilters first), which the service requires.
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
    if ($AssignTo -ne 'DoNotAssign') {
        $Capabilities = $(try { Get-CIPPTenantCapabilities -TenantFilter $TenantFilter } catch { $null })
        if ($Capabilities.Entra_Premium_Internet_Access -ne $true -and $Capabilities.Entra_Premium_Private_Access -ne $true) { $AssignTo = 'DoNotAssign' }
    }
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

    if ($ProfileState -eq 'enabled') {
        $DisabledLinks = @($TrafficProfile.policies).Where({ $_ -and $_.state -ne 'enabled' })
        $Expected.disabledPolicies = @()
        $Current.disabledPolicies = @($DisabledLinks.ForEach({ "$($_.policyName)" }) | Sort-Object)
        $LinkWrites = @($DisabledLinks.ForEach({ [pscustomobject]@{ profileId = $TrafficProfile.id; id = $_.id } }))

        $Rules = $TrafficProfile.assignmentRules
        $AssignmentType = "$($Rules.assignments.'@odata.type')"
        $IsAll = $AssignmentType -like '*forwardingProfileAssignmentsAllMembership'
        $IsEnumerated = $AssignmentType -like '*forwardingProfileAssignmentsEnumeratedMembership'
        $Assigned = @{}
        foreach ($Kind in 'users', 'devices', 'groups') { $Assigned[$Kind] = @(@($Rules.assignments.$Kind).Where({ $_.id }).ForEach({ "$($_.id)" })) }
        $HasEntries = $IsEnumerated -and ($Assigned.users.Count + $Assigned.devices.Count + $Assigned.groups.Count) -gt 0
        $Platforms = "$($Rules.devicePropertyFilters.platforms)"
        if (-not $Platforms) { $Platforms = 'windows,macOS,android,iOS' }
        $CurrentAssignment = if ($IsAll) { 'All users and devices' } elseif ($HasEntries) { 'Specific users, devices or groups' } elseif ($IsEnumerated) { 'Not assigned' } else { 'Not set' }
        $NewRules = {
            param($Assignments)
            [ordered]@{ devicePropertyFilters = [ordered]@{ platforms = $Platforms }; assignments = $Assignments }
        }

        switch ($AssignTo) {
            'AllDevicesAndUsers' {
                $Expected.assignment = 'All users and devices'
                $Current.assignment = $CurrentAssignment
                if (-not $IsAll) {
                    $AssignmentWrites = @([pscustomobject]@{ id = $TrafficProfile.id; assignmentRules = & $NewRules ([ordered]@{ '@odata.type' = '#microsoft.graph.networkaccess.forwardingProfileAssignmentsAllMembership' }) })
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
                        if (-not $IsEnumerated -or $Assigned.groups -notcontains "$($Group.id)") { $Missing.Add("$($Group.displayName)") }
                    }
                }
                $Expected.missingGroups = @()
                $Current.missingGroups = @($Missing | Sort-Object -Unique)
                $NewGroups = @($Resolved.Where({ $Assigned.groups -notcontains $_ }))
                if ($Resolved.Count -gt 0 -and (-not $IsEnumerated -or $NewGroups.Count -gt 0)) {
                    $Kept = if ($IsEnumerated) { $Assigned } else { @{ users = @(); devices = @(); groups = @() } }
                    $AllGroups = @(@($Kept.groups) + @($Resolved) | Sort-Object -Unique)
                    $AssignmentWrites = @([pscustomobject]@{
                            id              = $TrafficProfile.id
                            assignmentRules = & $NewRules ([ordered]@{
                                    '@odata.type' = '#microsoft.graph.networkaccess.forwardingProfileAssignmentsEnumeratedMembership'
                                    users         = @($Kept.users.ForEach({ [ordered]@{ id = $_ } }))
                                    devices       = @($Kept.devices.ForEach({ [ordered]@{ id = $_ } }))
                                    groups        = @($AllGroups.ForEach({ [ordered]@{ id = $_ } }))
                                })
                        })
                }
            }
        }
    }

    $CurrentObject = [pscustomobject]$Current
    $CurrentObject | Add-Member -NotePropertyName 'stateWrites' -NotePropertyValue $StateWrites
    $CurrentObject | Add-Member -NotePropertyName 'linkWrites' -NotePropertyValue $LinkWrites
    $CurrentObject | Add-Member -NotePropertyName 'assignmentWrites' -NotePropertyValue $AssignmentWrites
    @{ Expected = [pscustomobject]$Expected; Current = $CurrentObject }
}
