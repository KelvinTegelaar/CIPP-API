function Set-CIPPDBCacheAppRoleAssignments {
    <#
    .SYNOPSIS
        Caches application role assignments for a tenant

    .PARAMETER TenantFilter
        The tenant to cache app role assignments for

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
        Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message 'Caching app role assignments' -sev Debug

        # Get all service principals first
        $ServicePrincipals = New-GraphGetRequest -uri 'https://graph.microsoft.com/beta/servicePrincipals?$select=id,appId,displayName&$top=999&expand=appRoleAssignments' -tenantid $TenantFilter

        $AllAppRoleAssignments = [System.Collections.Generic.List[object]]::new()

        foreach ($SP in $ServicePrincipals) {
            try {
                $AppRoleAssignments = $SP.appRoleAssignments
                foreach ($Assignment in $AppRoleAssignments) {
                    # Enrich with service principal info
                    $Assignment | Add-Member -NotePropertyMembers ([ordered]@{
                            servicePrincipalDisplayName = $SP.displayName
                            servicePrincipalAppId       = $SP.appId
                        }) -Force
                    $AllAppRoleAssignments.Add($Assignment)
                }
            } catch {
                Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message "Failed to get app role assignments for $($SP.displayName): $($_.Exception.Message)" -sev Warning
            }
        }

        if ($AllAppRoleAssignments.Count -gt 0) {
            Add-CIPPDbItem -TenantFilter $TenantFilter -Type 'AppRoleAssignments' -Data $AllAppRoleAssignments -AddCount
            Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message "Cached $($AllAppRoleAssignments.Count) app role assignments" -sev Debug
        } else {
            # The service principal read succeeded and no assignments exist: write the authoritative
            # empty set so the Count marker records a completed collection and stale rows are cleared.
            Add-CIPPDbItem -TenantFilter $TenantFilter -Type 'AppRoleAssignments' -Data @() -AddCount -ClearOnEmpty
            Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message 'Cached 0 app role assignments (none found)' -sev Debug
        }
        $AllAppRoleAssignments = $null

    } catch {
        Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message "Failed to cache app role assignments: $($_.Exception.Message)" -sev Error
    }
}
