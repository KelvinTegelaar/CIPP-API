function Set-CIPPDBCacheAppRoleAssignments {
    <#
    .SYNOPSIS
        Caches application role assignments for a tenant

    .PARAMETER TenantFilter
        The tenant to cache app role assignments for
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$TenantFilter
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
                    $Assignment | Add-Member -NotePropertyName 'servicePrincipalDisplayName' -NotePropertyValue $SP.displayName -Force
                    $Assignment | Add-Member -NotePropertyName 'servicePrincipalAppId' -NotePropertyValue $SP.appId -Force
                    $AllAppRoleAssignments.Add($Assignment)
                }
            } catch {
                Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message "Failed to get app role assignments for $($SP.displayName): $($_.Exception.Message)" -sev Warning
            }
        }

        if ($AllAppRoleAssignments.Count -gt 0) {
            Add-CIPPDbItem -TenantFilter $TenantFilter -Type 'AppRoleAssignments' -Data $AllAppRoleAssignments
            Add-CIPPDbItem -TenantFilter $TenantFilter -Type 'AppRoleAssignments' -Data $AllAppRoleAssignments -Count
            Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message "Cached $($AllAppRoleAssignments.Count) app role assignments" -sev Debug
        }
        $AllAppRoleAssignments = $null

    } catch {
        Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message "Failed to cache app role assignments: $($_.Exception.Message)" -sev Error
    }
}
