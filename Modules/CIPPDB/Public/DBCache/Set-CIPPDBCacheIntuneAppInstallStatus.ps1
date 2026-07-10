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

    $ReportName = 'AppInstallStatusAggregate'

    try {
        $JobsTable = Get-CIPPTable -tablename 'IntuneReportJobs'
        $JobRow = Get-CIPPAzDataTableEntity @JobsTable -Filter "PartitionKey eq '$TenantFilter' and RowKey eq '$ReportName'"

        if (-not $JobRow) {
            # No pending job - the nightly submission was already consumed by a previous cache run
            # or never ran. Submit a new export job now so forced cache runs are self-sufficient.
            Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message "No $ReportName export job pending - submitting a new one" -sev Info
            $null = New-CIPPIntuneReportExportJob -TenantFilter $TenantFilter -ReportName $ReportName
            $JobRow = Get-CIPPAzDataTableEntity @JobsTable -Filter "PartitionKey eq '$TenantFilter' and RowKey eq '$ReportName'"
        }

        $JobId = $JobRow.JobId
        if (-not $JobId) {
            Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message 'IntuneReportJobs row missing JobId - removing' -sev Warning
            Remove-AzDataTableEntity @JobsTable -Entity $JobRow -Force -ErrorAction SilentlyContinue
            return
        }

        # Poll the export job until it completes. Jobs submitted by the nightly orchestrator are
        # long since completed and pass on the first check; freshly self-submitted jobs get a
        # bounded wait so a forced run still returns fresh data.
        $Deadline = [datetime]::UtcNow.AddMinutes(4)
        while ($true) {
            try {
                $Job = New-GraphGetRequest -uri "https://graph.microsoft.com/beta/deviceManagement/reports/exportJobs/$JobId" -tenantid $TenantFilter
            } catch {
                $ErrorMessage = Get-CippException -Exception $_
                Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message "$ReportName job $JobId not retrievable: $($ErrorMessage.NormalizedError)" -sev Warning -LogData $ErrorMessage
                Remove-AzDataTableEntity @JobsTable -Entity $JobRow -Force -ErrorAction SilentlyContinue
                return
            }

            if ($Job.status -eq 'completed') { break }
            if ($Job.status -eq 'failed') {
                Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message "$ReportName job $JobId failed" -sev Error
                Remove-AzDataTableEntity @JobsTable -Entity $JobRow -Force -ErrorAction SilentlyContinue
                return
            }
            if ([datetime]::UtcNow -ge $Deadline) {
                # Keep the job row so the next cache run can consume the result
                Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message "$ReportName job $JobId still '$($Job.status)' after waiting - the result will be cached on the next run" -sev Info
                return
            }
            Start-Sleep -Seconds 20
        }

        if (-not $Job.url) {
            Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message "$ReportName job $JobId completed but no url returned" -sev Error
            Remove-AzDataTableEntity @JobsTable -Entity $JobRow -Force -ErrorAction SilentlyContinue
            return
        }

        $ZipBytes = (Invoke-WebRequest -Uri $Job.url -UseBasicParsing -ErrorAction Stop).Content
        if ($ZipBytes -isnot [byte[]]) { throw "Expected binary content from $ReportName download" }

        $JsonText = $null
        $ZipStream = [System.IO.MemoryStream]::new($ZipBytes, $false)
        try {
            $Archive = [System.IO.Compression.ZipArchive]::new($ZipStream, [System.IO.Compression.ZipArchiveMode]::Read)
            try {
                $Entry = $Archive.Entries | Where-Object { $_.Name -like '*.json' } | Select-Object -First 1
                if (-not $Entry) { throw "No JSON entry in $ReportName archive" }
                $EntryStream = $Entry.Open()
                try {
                    $Reader = [System.IO.StreamReader]::new($EntryStream)
                    try { $JsonText = $Reader.ReadToEnd() } finally { $Reader.Dispose() }
                } finally { $EntryStream.Dispose() }
            } finally { $Archive.Dispose() }
        } finally {
            $ZipStream.Dispose()
            $ZipBytes = $null
        }

        $ExportRows = @(($JsonText | ConvertFrom-Json).values)
        $JsonText = $null

        $AppStatuses = foreach ($Row in $ExportRows) {
            if (-not $Row.ApplicationId) { continue }
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
        Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message "Cached $($AppStatuses.Count) app install status rows from export $JobId" -sev Info

        Remove-AzDataTableEntity @JobsTable -Entity $JobRow -Force -ErrorAction SilentlyContinue
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message "Failed to cache app install status: $($ErrorMessage.NormalizedError)" -sev Error -LogData $ErrorMessage
    }
}
