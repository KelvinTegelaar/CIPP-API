function Set-CIPPDBCacheDeviceEnrollmentConfigurations {
    <#
    .SYNOPSIS
        Caches all Intune device enrollment configurations for a tenant

    .DESCRIPTION
        Caches every deviceEnrollmentConfiguration row with its full settings payload
        (id, deviceEnrollmentConfigurationType, priority and all type-specific settings).
        This single cache serves AutopilotStatusPage, DefaultPlatformRestrictions and
        EnrollmentWindowsHelloForBusinessConfiguration.

    .PARAMETER TenantFilter
        The tenant to cache device enrollment configurations for

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
        $TestResult = Test-CIPPStandardLicense -StandardName 'DeviceEnrollmentConfigurationsCache' -TenantFilter $TenantFilter -Preset Intune -SkipLog
        if ($TestResult -eq $false) {
            Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message 'Tenant does not have Intune license, skipping device enrollment configurations cache' -sev Debug
            # A license skip is still a completed collection: record the authoritative empty set
            # so collect-on-miss does not re-run this collector forever on unlicensed tenants.
            Add-CIPPDbItem -TenantFilter $TenantFilter -Type 'DeviceEnrollmentConfigurations' -Data @() -AddCount -ClearOnEmpty
            return
        }

        Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message 'Caching device enrollment configurations' -sev Debug

        # -AsApp matches the old DefaultPlatformRestrictions / EnrollmentWindowsHelloForBusinessConfiguration
        # standards; app-only reads every configuration type regardless of delegated scopes.
        $Configurations = New-GraphGetRequest -uri 'https://graph.microsoft.com/beta/deviceManagement/deviceEnrollmentConfigurations?$top=999' -tenantid $TenantFilter -AsApp $true
        if (-not $Configurations) { $Configurations = @() }

        Add-CIPPDbItem -TenantFilter $TenantFilter -Type 'DeviceEnrollmentConfigurations' -Data @($Configurations) -AddCount

        Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message "Cached $(($Configurations | Measure-Object).Count) device enrollment configurations" -sev Debug
    } catch {
        Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message "Failed to cache device enrollment configurations: $($_.Exception.Message)" -sev Error
    }
}
