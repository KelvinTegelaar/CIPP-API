function Set-CIPPDBCacheIntuneAssignmentFilters {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$TenantFilter,
        [string]$QueueId
    )

    try {
        $TestResult = Test-CIPPStandardLicense -StandardName 'IntuneAssignmentFiltersCache' -TenantFilter $TenantFilter -Preset Intune -SkipLog
        if ($TestResult -eq $false) {
            Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message 'Tenant does not have Intune license, skipping assignment filters cache' -sev Debug
            return
        }

        Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message 'Caching Intune assignment filters' -sev Debug
        $AssignmentFilters = New-GraphGetRequest -uri 'https://graph.microsoft.com/beta/deviceManagement/assignmentFilters' -tenantid $TenantFilter
        if (-not $AssignmentFilters) { $AssignmentFilters = @() }

        Add-CIPPDbItem -TenantFilter $TenantFilter -Type 'IntuneAssignmentFilters' -Data @($AssignmentFilters)
        Add-CIPPDbItem -TenantFilter $TenantFilter -Type 'IntuneAssignmentFilters' -Data @($AssignmentFilters) -Count

        Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message "Cached $(($AssignmentFilters | Measure-Object).Count) assignment filters" -sev Debug
    } catch {
        Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message "Failed to cache assignment filters: $($_.Exception.Message)" -sev Error -LogData (Get-CippException -Exception $_)
    }
}
