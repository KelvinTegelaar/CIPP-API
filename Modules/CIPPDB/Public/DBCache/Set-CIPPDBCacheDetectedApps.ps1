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
            Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message "No $ReportName job submitted - skipping detected apps cache" -sev Info
            return
        }

        $JobId = $JobRow.JobId
        if (-not $JobId) {
            Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message "IntuneReportJobs row missing JobId - removing" -sev Warning
            Remove-AzDataTableEntity @JobsTable -Entity $JobRow -Force -ErrorAction SilentlyContinue
            return
        }

        try {
            $Job = New-GraphGetRequest -uri "https://graph.microsoft.com/beta/deviceManagement/reports/exportJobs/$JobId" -tenantid $TenantFilter
        } catch {
            $ErrorMessage = Get-CippException -Exception $_
            Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message "$ReportName job $JobId not retrievable: $($ErrorMessage.NormalizedError)" -sev Warning -LogData $ErrorMessage
            Remove-AzDataTableEntity @JobsTable -Entity $JobRow -Force -ErrorAction SilentlyContinue
            return
        }

        switch ($Job.status) {
            'completed' { }
            'failed' {
                Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message "$ReportName job $JobId failed" -sev Error
                Remove-AzDataTableEntity @JobsTable -Entity $JobRow -Force -ErrorAction SilentlyContinue
                return
            }
            default {
                Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message "$ReportName job $JobId still '$($Job.status)' - skipping" -sev Info
                return
            }
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

        $AppsByKey = @{}
        foreach ($Row in $ExportRows) {
            $AppId = $Row.ApplicationKey
            if (-not $AppId) { continue }
            if (-not $AppsByKey.ContainsKey($AppId)) {
                $AppsByKey[$AppId] = [pscustomobject]@{
                    id             = $AppId
                    displayName    = $Row.ApplicationName
                    version        = $Row.ApplicationVersion
                    publisher      = $Row.ApplicationPublisher
                    platform       = $Row.Platform
                    deviceCount    = 0
                    managedDevices = [System.Collections.Generic.List[object]]::new()
                }
            }
            $App = $AppsByKey[$AppId]
            $App.managedDevices.Add([pscustomobject]@{
                id                = $Row.DeviceId
                deviceName        = $Row.DeviceName
                osVersion         = $Row.OSVersion
                platform          = $Row.Platform
                userId            = $Row.UserId
                userPrincipalName = $Row.UserName
                emailAddress      = $Row.EmailAddress
            })
            $App.deviceCount++
        }

        $DetectedApps = @($AppsByKey.Values)
        Add-CIPPDbItem -TenantFilter $TenantFilter -Type 'DetectedApps' -Data $DetectedApps -AddCount
        Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message "Cached $($DetectedApps.Count) detected apps with devices from export $JobId" -sev Info

        Remove-AzDataTableEntity @JobsTable -Entity $JobRow -Force -ErrorAction SilentlyContinue
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message "Failed to cache detected apps: $($ErrorMessage.NormalizedError)" -sev Error -LogData $ErrorMessage
    }
}
