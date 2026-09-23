function Set-CIPPDBCacheDetectedApps {
    <#
    .SYNOPSIS
        Caches detected apps using the AppInvRawData export submitted earlier,
        enriched with the live /detectedApps catalog.

    .PARAMETER TenantFilter
        The tenant to cache detected apps for.

    .PARAMETER QueueId
        Optional queue ID for progress tracking.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$TenantFilter,
        [string]$QueueId
    )

    $ReportName = 'AppInvRawData'

    try {
        $JobsTable = Get-CIPPTable -tablename 'IntuneReportJobs'
        $JobRow = Get-CIPPAzDataTableEntity @JobsTable -Filter "PartitionKey eq '$TenantFilter' and RowKey eq '$ReportName'"

        if (-not $JobRow) {
            Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message "No $ReportName export job pending - submitting a new one" -sev Info
            $null = New-CIPPIntuneReportExportJob -TenantFilter $TenantFilter -ReportName $ReportName
            $JobRow = Get-CIPPAzDataTableEntity @JobsTable -Filter "PartitionKey eq '$TenantFilter' and RowKey eq '$ReportName'"
        }

        $JobId = $JobRow.JobId
        if (-not $JobId) {
            Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message "IntuneReportJobs row missing JobId - removing" -sev Warning
            Remove-CIPPAzDataTableEntity @JobsTable -Entity $JobRow -Force -ErrorAction SilentlyContinue
            return
        }


        $Deadline = [datetime]::UtcNow.AddMinutes(4)
        while ($true) {
            try {
                $Job = New-GraphGetRequest -uri "https://graph.microsoft.com/beta/deviceManagement/reports/exportJobs/$JobId" -tenantid $TenantFilter
            } catch {
                $ErrorMessage = Get-CippException -Exception $_
                Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message "$ReportName job $JobId not retrievable: $($ErrorMessage.NormalizedError)" -sev Warning -LogData $ErrorMessage
                Remove-CIPPAzDataTableEntity @JobsTable -Entity $JobRow -Force -ErrorAction SilentlyContinue
                return
            }

            if ($Job.status -eq 'completed') { break }
            if ($Job.status -eq 'failed') {
                Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message "$ReportName job $JobId failed" -sev Error
                Remove-CIPPAzDataTableEntity @JobsTable -Entity $JobRow -Force -ErrorAction SilentlyContinue
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
            Remove-CIPPAzDataTableEntity @JobsTable -Entity $JobRow -Force -ErrorAction SilentlyContinue
            return
        }

        # Rows stream off the export download and are folded as they arrive, so the export is never
        # held whole. The export has one row per device x app, and every device repeats under each
        # app it has installed, so one device object per distinct device tuple is shared by all of
        # its apps rather than a copy per row. The stored JSON is identical either way.
        $AppsByKey = @{}
        $DeviceByTuple = [System.Collections.Generic.Dictionary[string, object]]::new()
        Get-CIPPIntuneReportExportRows -Url $Job.url | ForEach-Object {
            $AppId = $_.ApplicationKey
            if (-not $AppId) { return }
            $App = $AppsByKey[$AppId]
            if (-not $App) {
                $App = [pscustomobject]@{
                    id             = $AppId
                    displayName    = $_.ApplicationName
                    version        = $_.ApplicationVersion
                    publisher      = $_.ApplicationPublisher
                    platform       = $_.Platform
                    deviceCount    = 0
                    managedDevices = [System.Collections.Generic.List[object]]::new()
                }
                $AppsByKey[$AppId] = $App
            }
            $DeviceKey = "$($_.DeviceId)`0$($_.DeviceName)`0$($_.OSVersion)`0$($_.Platform)`0$($_.UserId)`0$($_.UserName)`0$($_.EmailAddress)"
            $Device = $null
            if (-not $DeviceByTuple.TryGetValue($DeviceKey, [ref]$Device)) {
                $Device = [pscustomobject]@{
                    id                = $_.DeviceId
                    deviceName        = $_.DeviceName
                    osVersion         = $_.OSVersion
                    platform          = $_.Platform
                    userId            = $_.UserId
                    userPrincipalName = $_.UserName
                    emailAddress      = $_.EmailAddress
                }
                $DeviceByTuple[$DeviceKey] = $Device
            }
            $App.managedDevices.Add($Device)
            $App.deviceCount++
        }
        $DeviceByTuple = $null

        # Streamed into the writer instead of copied into an array first: Add-CIPPDbItem batches
        # internally, so this drops a full-length copy of the app list at the point where the
        # grouped devices are still live.
        $DetectedAppCount = $AppsByKey.Count
        $AppsByKey.Values | Add-CIPPDbItem -TenantFilter $TenantFilter -Type 'DetectedApps' -AddCount
        $AppsByKey = $null
        Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message "Cached $DetectedAppCount detected apps with devices from export $JobId" -sev Info

        Remove-CIPPAzDataTableEntity @JobsTable -Entity $JobRow -Force -ErrorAction SilentlyContinue
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message "Failed to cache detected apps: $($ErrorMessage.NormalizedError)" -sev Error -LogData $ErrorMessage
    }
}
