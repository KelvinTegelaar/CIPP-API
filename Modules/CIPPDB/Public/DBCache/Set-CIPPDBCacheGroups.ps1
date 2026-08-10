function Set-CIPPDBCacheGroups {
    <#
    .SYNOPSIS
        Caches all groups for a tenant

    .PARAMETER TenantFilter
        The tenant to cache groups for

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
        Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message 'Caching groups' -sev Debug

        $GroupSelect = 'id,createdDateTime,displayName,description,mail,mailEnabled,mailNickname,resourceProvisioningOptions,securityEnabled,visibility,organizationId,onPremisesSamAccountName,membershipRule,groupTypes,onPremisesSyncEnabled,assignedLicenses,licenseProcessingState'
        $Groups = New-GraphGetRequest -uri "https://graph.microsoft.com/beta/groups?`$top=999&`$select=$GroupSelect&`$expand=owners(`$select=id,displayName,userPrincipalName)" -tenantid $TenantFilter

        # Build bulk request for group members
        $MemberRequests = $Groups | ForEach-Object {
            if ($_.id) {
                [PSCustomObject]@{
                    id     = $_.id
                    method = 'GET'
                    url    = "/groups/$($_.id)/members?`$top=999&`$select=id,displayName,userPrincipalName"
                }
            }
        }

        # Index the member responses by group id. The previous per-group
        # 'Where-Object { $_.id -eq $Group.id }' rescanned the whole response array for every
        # group, which is O(groups x groups) - 100M comparisons on a 10k-group tenant.
        $MembersByGroupId = @{}
        # Tracks which shape the rows take: groups fetched with a member lookup carry a
        # 'members' property (null when the lookup returned nothing for that group), groups
        # fetched without one omit the property entirely. Keyed off whether the lookup ran,
        # not off whether it returned anything, so an empty response still yields the
        # members-shaped row the previous implementation produced.
        $HasMembers = [bool]$MemberRequests
        if ($HasMembers) {
            Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message 'Fetching group members' -sev Debug
            $MemberResults = New-GraphBulkRequest -Requests @($MemberRequests) -tenantid $TenantFilter
            foreach ($Result in $MemberResults) {
                if ($Result.id) { $MembersByGroupId[$Result.id] = $Result.body.value }
            }
            $MemberResults = $null
        }
        $MemberRequests = $null

        # Project and emit one group at a time: Add-CIPPDbItem batches internally, so peak
        # retention is a batch of rows rather than every group (with its whole member list)
        # plus a second materialised array. Each group's members are dropped from the index
        # once written, so membership becomes collectable as the run progresses.
        # Properties are applied in a single Add-Member call - adding them one at a time
        # rebuilds the object's property bag on every call. The [ordered] dictionary keeps
        # the emitted JSON property order identical to the previous sequential adds.
        & {
            foreach ($Group in $Groups) {
                $groupType = if ($Group.groupTypes -contains 'Unified') { 'Microsoft 365' }
                elseif ($Group.mailEnabled -and $Group.securityEnabled) { 'Mail-Enabled Security' }
                elseif (-not $Group.mailEnabled -and $Group.securityEnabled) { 'Security' }
                elseif ([string]::IsNullOrEmpty($Group.groupTypes) -and $Group.mailEnabled -and -not $Group.securityEnabled) { 'Distribution List' }
                else { 'Unknown' }
                $calculatedGroupType = if ($Group.groupTypes -contains 'Unified') { 'm365' }
                elseif ($Group.mailEnabled -and $Group.securityEnabled) { 'security' }
                elseif (-not $Group.mailEnabled -and $Group.securityEnabled) { 'generic' }
                elseif ([string]::IsNullOrEmpty($Group.groupTypes) -and $Group.mailEnabled -and -not $Group.securityEnabled) { 'distributionList' }
                else { 'unknown' }

                $NoteProperties = [ordered]@{}
                if ($HasMembers) {
                    $NoteProperties['members'] = $MembersByGroupId[$Group.id]
                    $MembersByGroupId.Remove($Group.id)
                }
                $NoteProperties['primDomain'] = ($Group.mail -split '@' | Select-Object -Last 1)
                $NoteProperties['teamsEnabled'] = ($Group.resourceProvisioningOptions -contains 'Team')
                $NoteProperties['dynamicGroupBool'] = ($Group.groupTypes -contains 'DynamicMembership')
                $NoteProperties['groupType'] = $groupType
                $NoteProperties['calculatedGroupType'] = $calculatedGroupType

                $Group | Add-Member -NotePropertyMembers $NoteProperties -Force
                $Group
            }
        } | Add-CIPPDbItem -TenantFilter $TenantFilter -Type 'Groups' -AddCount

        $Groups = $null
        $MembersByGroupId = $null

        Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message 'Cached groups with members and owners successfully' -sev Debug

    } catch {
        Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter `
            -message "Failed to cache groups: $($_.Exception.Message)" -sev Error
    }
}
