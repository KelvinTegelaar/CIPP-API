function Set-CIPPDBCacheManagedDeviceCleanupRules {
    <#
    .SYNOPSIS
        Caches Intune managed device cleanup rules for a tenant

    .DESCRIPTION
        Caches deviceManagement/managedDeviceCleanupRules (deviceInactivityBeforeRetirementInDays
        and related settings) used by the intuneDeviceRetirementDays standard.

    .PARAMETER TenantFilter
        The tenant to cache managed device cleanup rules for

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
        $TestResult = Test-CIPPStandardLicense -StandardName 'ManagedDeviceCleanupRulesCache' -TenantFilter $TenantFilter -Preset Intune -SkipLog
        if ($TestResult -eq $false) {
            Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message 'Tenant does not have Intune license, skipping managed device cleanup rules cache' -sev Debug
            return
        }

        Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message 'Caching managed device cleanup rules' -sev Debug

        $CleanupRules = New-GraphGetRequest -uri 'https://graph.microsoft.com/beta/deviceManagement/managedDeviceCleanupRules' -tenantid $TenantFilter
        if (-not $CleanupRules) { $CleanupRules = @() }

        Add-CIPPDbItem -TenantFilter $TenantFilter -Type 'ManagedDeviceCleanupRules' -Data @($CleanupRules) -AddCount

        Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message "Cached $(($CleanupRules | Measure-Object).Count) managed device cleanup rules" -sev Debug
    } catch {
        Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message "Failed to cache managed device cleanup rules: $($_.Exception.Message)" -sev Error
    }
}
