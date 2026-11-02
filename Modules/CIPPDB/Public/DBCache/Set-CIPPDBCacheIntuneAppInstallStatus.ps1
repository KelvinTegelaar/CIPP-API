function Set-CIPPDBCacheIntuneAppInstallStatus {
    <#
    .SYNOPSIS
        Caches per-application install status counts from the AppInstallStatusAggregate
        export submitted earlier.

    .DESCRIPTION
        The AppInstallStatusAggregate report is the only tenant-wide app install report Intune
        exposes without a per-app filter, so it carries rollup counts (FailedDeviceCount etc.)
        rather than per-device detail. Get-CIPPAlertIntunePolicyConflicts reads the cached rows
        to flag applications that are failing to install.

    .PARAMETER TenantFilter
        The tenant to cache app install status for.

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
        $Export = Get-CIPPIntuneReportExportJob -TenantFilter $TenantFilter -ReportName 'AppInstallStatusAggregate'
        if (-not $Export) { return }

        # Rows stream off the export download, so only the rollup rows are ever held.
        $AppStatuses = Get-CIPPIntuneReportExportRows -Url $Export.Url | ForEach-Object {
            $Row = $_
            if (-not $Row.ApplicationId) { return }
            [pscustomobject]@{
                id                        = $Row.ApplicationId
                displayName               = $Row.DisplayName
                publisher                 = $Row.Publisher
                platform                  = $Row.AppPlatform ?? $Row.Platform
                appVersion                = $Row.AppVersion
                installedDeviceCount      = [int]($Row.InstalledDeviceCount ?? 0)
                failedDeviceCount         = [int]($Row.FailedDeviceCount ?? 0)
                failedUserCount           = [int]($Row.FailedUserCount ?? 0)
                pendingInstallDeviceCount = [int]($Row.PendingInstallDeviceCount ?? 0)
                notInstalledDeviceCount   = [int]($Row.NotInstalledDeviceCount ?? 0)
                failedDevicePercentage    = [double]($Row.FailedDevicePercentage ?? 0)
            }
        }
        $AppStatuses = @($AppStatuses)

        Add-CIPPDbItem -TenantFilter $TenantFilter -Type 'IntuneAppInstallStatusAggregate' -Data $AppStatuses -AddCount
        Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message "Cached $($AppStatuses.Count) app install status rows from export $($Export.JobId)" -sev Info
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message "Failed to cache app install status: $($ErrorMessage.NormalizedError)" -sev Error -LogData $ErrorMessage
    } finally {
        if ($Export) {
            $JobsTable = Get-CIPPTable -tablename 'IntuneReportJobs'
            Remove-CIPPAzDataTableEntity @JobsTable -Entity $Export.Row -Force -ErrorAction SilentlyContinue
        }
    }
}
