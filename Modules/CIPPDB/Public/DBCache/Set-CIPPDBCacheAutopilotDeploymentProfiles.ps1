function Set-CIPPDBCacheAutopilotDeploymentProfiles {
    <#
    .SYNOPSIS
        Caches Windows Autopilot deployment profiles for a tenant

    .PARAMETER TenantFilter
        The tenant to cache Autopilot deployment profiles for

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
        $TestResult = Test-CIPPStandardLicense -StandardName 'AutopilotDeploymentProfilesCache' -TenantFilter $TenantFilter -Preset Intune -SkipLog
        if ($TestResult -eq $false) {
            Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message 'Tenant does not have Intune license, skipping Autopilot deployment profiles cache' -sev Debug
            # A license skip is still a completed collection: record the authoritative empty set
            # so collect-on-miss does not re-run this collector forever on unlicensed tenants.
            Add-CIPPDbItem -TenantFilter $TenantFilter -Type 'AutopilotDeploymentProfiles' -Data @() -AddCount -ClearOnEmpty
            return
        }

        Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message 'Caching Autopilot deployment profiles' -sev Debug

        $Profiles = New-GraphGetRequest -uri 'https://graph.microsoft.com/beta/deviceManagement/windowsAutopilotDeploymentProfiles?$top=999&$expand=assignments' -tenantid $TenantFilter
        if (-not $Profiles) { $Profiles = @() }

        Add-CIPPDbItem -TenantFilter $TenantFilter -Type 'AutopilotDeploymentProfiles' -Data @($Profiles) -AddCount
        Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message "Cached $(($Profiles | Measure-Object).Count) Autopilot deployment profiles" -sev Debug
    } catch {
        Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message "Failed to cache Autopilot deployment profiles: $($_.Exception.Message)" -sev Error
    }
}
