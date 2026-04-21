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

        $Groups = New-GraphGetRequest -uri 'https://graph.microsoft.com/beta/groups?$top=999&$select=id,displayName,groupTypes,mail,mailEnabled,securityEnabled,membershipRule,onPremisesSyncEnabled' -tenantid $TenantFilter

        # Build bulk request for group members
        $MemberRequests = $Groups | ForEach-Object {
            if ($_.id) {
                [PSCustomObject]@{
                    id     = $_.id
                    method = 'GET'
                    url    = "/groups/$($_.id)/members?`$select=id,displayName,userPrincipalName"
                }
            }
        }

        if ($MemberRequests) {
            Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message 'Fetching group members' -sev Debug
            $MemberResults = New-GraphBulkRequest -Requests @($MemberRequests) -tenantid $TenantFilter

            # Add members to each group object
            $GroupsWithMembers = foreach ($Group in $Groups) {
                $Members = ($MemberResults | Where-Object { $_.id -eq $Group.id }).body.value
                $Group | Add-Member -NotePropertyName 'members' -NotePropertyValue $Members -Force
                $Group
            }

            Add-CIPPDbItem -TenantFilter $TenantFilter -Type 'Groups' -Data $GroupsWithMembers
            Add-CIPPDbItem -TenantFilter $TenantFilter -Type 'Groups' -Data $GroupsWithMembers -Count
            $Groups = $null
            $GroupsWithMembers = $null
        } else {
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
