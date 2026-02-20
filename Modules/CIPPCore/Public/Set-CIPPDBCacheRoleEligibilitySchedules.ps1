function Set-CIPPDBCacheRoleEligibilitySchedules {
    <#
    .SYNOPSIS
        Caches role eligibility schedules for a tenant

    .PARAMETER TenantFilter
        The tenant to cache role eligibility schedules for
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$TenantFilter
    )

    try {
        Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message 'Caching role eligibility schedules' -sev Debug
        $RoleEligibilitySchedules = New-GraphGetRequest -uri 'https://graph.microsoft.com/beta/roleManagement/directory/roleEligibilitySchedules' -tenantid $TenantFilter
        Add-CIPPDbItem -TenantFilter $TenantFilter -Type 'RoleEligibilitySchedules' -Data @($RoleEligibilitySchedules)
        $RoleEligibilitySchedules = $null

        Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message 'Cached role eligibility schedules successfully' -sev Debug

    } catch {
        Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message "Failed to cache role eligibility schedules: $($_.Exception.Message)" -sev Error
    }
}
