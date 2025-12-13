function Push-AuditLogIngestionDownload {
    <#
    .SYNOPSIS
        Download and cache audit log content blobs
    .DESCRIPTION
        Activity function that downloads a single content blob and caches records
    .FUNCTIONALITY
        Entrypoint
    #>
    param($Item)

    try {
        $TenantFilter = $Item.TenantFilter
        $ContentType = $Item.ContentType
        $ContentItem = $Item.ContentItem
        $CacheWebhooksTable = Get-CippTable -tablename 'CacheWebhooks'

        $DownloadStopwatch = [System.Diagnostics.Stopwatch]::StartNew()

        Write-LogMessage -API 'AuditLogIngestion' -tenant $TenantFilter -message "Downloading content blob for $ContentType" -sev Debug

        $BlobParams = @{
            scope    = 'https://manage.office.com/.default'
            Uri      = $ContentItem.contentUri
            TenantId = $TenantFilter
        }

        $BlobResponse = New-GraphGetRequest @BlobParams -ErrorAction Stop

        if ($BlobResponse -is [string]) {
            $AuditRecords = $BlobResponse | ConvertFrom-Json -Depth 5
        } else {
            $AuditRecords = $BlobResponse
        }

        if (!$AuditRecords) {
            Write-LogMessage -API 'AuditLogIngestion' -tenant $TenantFilter -message "No records in blob for $ContentType" -sev Warn
            $DownloadStopwatch.Stop()
            return @{
                Success          = $true
                ProcessedRecords = 0
                Timings          = @{ Download = $DownloadStopwatch.Elapsed.TotalMilliseconds }
            }
        }

        Write-LogMessage -API 'AuditLogIngestion' -tenant $TenantFilter -message "Caching $($AuditRecords.Count) audit records for $ContentType" -sev Debug

        $CacheStopwatch = [System.Diagnostics.Stopwatch]::StartNew()
        $CacheEntities = [System.Collections.Generic.List[hashtable]]::new()
        foreach ($Record in $AuditRecords) {
            $CacheEntities.Add(@{
                    RowKey       = $Record.Id
                    PartitionKey = $TenantFilter
                    JSON         = [string]($Record | ConvertTo-Json -Depth 10 -Compress)
                    ContentId    = $ContentItem.contentId
                    ContentType  = $ContentType
                })
        }

        if ($CacheEntities.Count -gt 0) {
            try {
                Add-CIPPAzDataTableEntity @CacheWebhooksTable -Entity $CacheEntities -Force
            } catch {
                Write-LogMessage -API 'AuditLogIngestion' -tenant $TenantFilter -message "Failed to batch cache records for $ContentType : $($_.Exception.Message)" -sev Error
                throw
            }
        }
        $CacheStopwatch.Stop()

        $DownloadStopwatch.Stop()

        return @{
            Success          = $true
            TenantFilter     = $TenantFilter
            ContentType      = $ContentType
            ProcessedRecords = $CacheEntities.Count
            ContentCreated   = [DateTime]$ContentItem.contentCreated
            ContentId        = $ContentItem.contentId
            Timings          = @{
                Download = $DownloadStopwatch.Elapsed.TotalMilliseconds
                Cache    = $CacheStopwatch.Elapsed.TotalMilliseconds
            }
        }

    } catch {
        Write-LogMessage -API 'AuditLogIngestion' -tenant $Item.TenantFilter -message "Error downloading content blob: $($_.Exception.Message)" -sev Error -LogData (Get-CippException -Exception $_)
        return @{
            Success = $false
            Error   = $_.Exception.Message
        }
    }
}
