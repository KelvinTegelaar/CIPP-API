function Set-CIPPDBCacheRoleAssignmentScheduleInstances {
    <#
    .SYNOPSIS
        Caches role assignment schedule instances for a tenant

    .PARAMETER TenantFilter
        The tenant to cache role assignment schedule instances for

    .PARAMETER QueueId
        The queue ID to update with total tasks (optional)
    #>
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [string]$TenantFilter,
        [string]$QueueId
    )

    try {
        Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message 'Caching role assignment schedule instances' -sev Debug
        # -AsApp is required: the RoleManagement.*.Directory grant is an APPLICATION permission,
        # so it only appears in an app-only token. The default delegated path (service account +
        # GDAP) fails with "Attempted to perform an unauthorized operation" because PIM reads via
        # delegated access additionally need the signed-in user to hold a directory role such as
        # Privileged Role Administrator, which GDAP does not grant.
        # $expand=principal is required by Get-CippDbRoleMembers, which reads
        # $member.principal.displayName/.userPrincipalName/.'@odata.type'. The API returns only
        # principalId (a GUID) by default, so without this those all resolve to $null and every
        # role member surfaces with a blank name.
        $Uri = 'https://graph.microsoft.com/v1.0/roleManagement/directory/roleAssignmentScheduleInstances?$expand=principal'
        New-GraphGetRequest -Uri $Uri -tenantid $TenantFilter -AsApp $true -Stream |
            Add-CIPPDbItem -TenantFilter $TenantFilter -Type 'RoleAssignmentScheduleInstances' -AddCount

        Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message 'Cached role assignment schedule instances successfully' -sev Debug
    } catch {
        Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message "Failed to cache role assignment schedule instances: $($_.Exception.Message)" -sev Error
    }
}
