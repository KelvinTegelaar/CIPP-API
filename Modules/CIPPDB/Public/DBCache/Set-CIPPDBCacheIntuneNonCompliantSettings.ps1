function Set-CIPPDBCacheIntuneNonCompliantSettings {
    <#
    .SYNOPSIS
        Caches every failing compliance setting on every non-compliant device from the
        NoncompliantDevicesAndSettingsV3 export submitted earlier.

    .DESCRIPTION
        One row per device per failing setting, the same data as Intune's Noncompliant devices and
        settings report. The synchronous getNoncompliantDevicesAndSettingsReport action answers 403
        for CIPP (delegated and app-only), so the export is the only way in. Read by
        Invoke-ListDeviceNonCompliance for the Non-Compliant Devices page.

    .PARAMETER TenantFilter
        The tenant to cache non-compliant settings for.

    .PARAMETER QueueId
        Optional queue ID for progress tracking.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$TenantFilter,
        [string]$QueueId
    )

    $Export = $null
    try {
        $Export = Get-CIPPIntuneReportExportJob -TenantFilter $TenantFilter -ReportName 'NoncompliantDevicesAndSettingsV3'
        if (-not $Export) { return }

        $Settings = Get-CIPPIntuneReportExportRows -Url $Export.Url | ForEach-Object {
            $Row = $_
            if (-not $Row.DeviceId) { return }
            [pscustomobject]@{
                id                = "$($Row.DeviceId)-$($Row.PolicyName)-$($Row.SettingName)"
                deviceId          = $Row.DeviceId
                deviceName        = $Row.DeviceName
                userPrincipalName = $Row.UPN
                os                = $Row.OS
                osVersion         = $Row.OSVersion
                policyName        = $Row.PolicyName
                settingName       = $Row.SettingNm ?? $Row.SettingName
                settingStatus     = $Row.SettingStatus
                errorCode         = $Row.ErrorCode
            }
        }
        $Settings = @($Settings)

        # No rows is the healthy state, so an empty export must clear the previous run's failures
        Add-CIPPDbItem -TenantFilter $TenantFilter -Type 'IntuneNonCompliantSettings' -Data $Settings -AddCount -ClearOnEmpty
        Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message "Cached $($Settings.Count) non-compliant setting rows from export $($Export.JobId)" -sev Info
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message "Failed to cache non-compliant settings: $($ErrorMessage.NormalizedError)" -sev Error -LogData $ErrorMessage
    } finally {
        if ($Export) {
            $JobsTable = Get-CIPPTable -tablename 'IntuneReportJobs'
            Remove-CIPPAzDataTableEntity @JobsTable -Entity $Export.Row -Force -ErrorAction SilentlyContinue
        }
    }
}
