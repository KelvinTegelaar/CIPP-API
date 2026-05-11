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
        $Groups = New-GraphGetRequest -uri "https://graph.microsoft.com/beta/groups?`$top=999&`$select=$GroupSelect" -tenantid $TenantFilter

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

        if ($MemberRequests) {
            Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message 'Fetching group members' -sev Debug
            $MemberResults = New-GraphBulkRequest -Requests @($MemberRequests) -tenantid $TenantFilter

            # Add members and computed properties to each group object
            $GroupsWithMembers = foreach ($Group in $Groups) {
                $Members = ($MemberResults | Where-Object { $_.id -eq $Group.id }).body.value
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
                $Group | Add-Member -NotePropertyName 'members' -NotePropertyValue $Members -Force
                $Group | Add-Member -NotePropertyName 'primDomain' -NotePropertyValue ($Group.mail -split '@' | Select-Object -Last 1) -Force
                $Group | Add-Member -NotePropertyName 'teamsEnabled' -NotePropertyValue ($Group.resourceProvisioningOptions -contains 'Team') -Force
                $Group | Add-Member -NotePropertyName 'dynamicGroupBool' -NotePropertyValue ($Group.groupTypes -contains 'DynamicMembership') -Force
                $Group | Add-Member -NotePropertyName 'groupType' -NotePropertyValue $groupType -Force
                $Group | Add-Member -NotePropertyName 'calculatedGroupType' -NotePropertyValue $calculatedGroupType -Force
                $Group
            }

            Add-CIPPDbItem -TenantFilter $TenantFilter -Type 'Groups' -Data $GroupsWithMembers
            Add-CIPPDbItem -TenantFilter $TenantFilter -Type 'Groups' -Data $GroupsWithMembers -Count
            $Groups = $null
            $GroupsWithMembers = $null
        } else {
            $Groups = foreach ($Group in $Groups) {
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
                $Group | Add-Member -NotePropertyName 'primDomain' -NotePropertyValue ($Group.mail -split '@' | Select-Object -Last 1) -Force
                $Group | Add-Member -NotePropertyName 'teamsEnabled' -NotePropertyValue ($Group.resourceProvisioningOptions -contains 'Team') -Force
                $Group | Add-Member -NotePropertyName 'dynamicGroupBool' -NotePropertyValue ($Group.groupTypes -contains 'DynamicMembership') -Force
                $Group | Add-Member -NotePropertyName 'groupType' -NotePropertyValue $groupType -Force
                $Group | Add-Member -NotePropertyName 'calculatedGroupType' -NotePropertyValue $calculatedGroupType -Force
                $Group
            }
            Add-CIPPDbItem -TenantFilter $TenantFilter -Type 'Groups' -Data $Groups
            Add-CIPPDbItem -TenantFilter $TenantFilter -Type 'Groups' -Data $Groups -Count
            $Groups = $null
        }

        Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message 'Cached groups with members successfully' -sev Debug

    } catch {
        Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter `
            -message "Failed to cache groups: $($_.Exception.Message)" -sev Error
    }
}
