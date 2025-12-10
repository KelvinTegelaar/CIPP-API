function Push-AuditLogIngestion {
    <#
  .FUNCTIONALITY
  Entrypoint
  #>
    param($Item)

    $TenantFilter = $Item.TenantFilter
    $TenantId = $Item.TenantId
    $ContentTypes = $Item.ContentTypes

    try {
        Write-LogMessage -API 'AuditLogIngestion' -tenant $TenantFilter -message 'Starting Management API ingestion for tenant' -sev Info
        $AuditLogStateTable = Get-CippTable -TableName 'AuditLogState'
        $CacheWebhooksTable = Get-CippTable -TableName 'CacheWebhooks'
        Write-LogMessage -API 'AuditLogIngestion' -tenant $TenantFilter -message "Content types to process: $($ContentTypes -join ', ')" -sev Info
        foreach ($ContentType in $ContentTypes) {
            $StateRowKey = "$TenantFilter-$ContentType"
            $StateEntity = Get-CIPPAzDataTableEntity @AuditLogStateTable -Filter "PartitionKey eq 'AuditLogState' and RowKey eq '$StateRowKey'"
            if ($StateEntity -and $StateEntity.SubscriptionEnabled) {
                Write-LogMessage -API 'AuditLogIngestion' -tenant $TenantFilter -message "Subscription already enabled for $ContentType" -sev Debug
                continue
            }
            $SubscriptionUri = "https://manage.office.com/api/v1.0/$TenantId/activity/feed/subscriptions/start?contentType=$ContentType"
            $SubscriptionParams = @{
                scope    = 'https://manage.office.com/.default'
                Uri      = $SubscriptionUri
                Method   = 'POST'
                TenantId = $TenantFilter
            }
            try {
                Write-LogMessage -API 'AuditLogIngestion' -tenant $TenantFilter -message "Starting subscription for $ContentType" -sev Debug
                $null = New-GraphPostRequest @SubscriptionParams -ErrorAction Stop
                Write-LogMessage -API 'AuditLogIngestion' -tenant $TenantFilter -message "Successfully started subscription for $ContentType" -sev Info

                $StateEntity = @{
                    PartitionKey        = 'AuditLogState'
                    RowKey              = $StateRowKey
                    SubscriptionEnabled = $true
                    ContentType         = $ContentType
                }
                Add-CIPPAzDataTableEntity @AuditLogStateTable -Entity $StateEntity -Force

            } catch {
                if ($_.Exception.Message -match 'AADSTS65001') {
                    if ($StateEntity -and $StateEntity.PermissionsUpdated) {
                        Write-LogMessage -API 'AuditLogIngestion' -tenant $TenantFilter -message "Permissions have already been updated for $ContentType, skipping re-attempt" -sev Warn
                        continue
                    }
                    Write-LogMessage -API 'AuditLogIngestion' -tenant $TenantFilter -message 'This tenant is missing permissions for reading the audit logs. Starting a permissions update' -sev error
                    Write-Host "Updating SAM permissions for tenant: $TenantFilter"
                    Update-CippSamPermissions -UpdatedBy 'CIPP-API'
                    Write-Host "Re-adding delegated permission for tenant: $TenantFilter"
                    Add-CIPPDelegatedPermission -RequiredResourceAccess 'CIPPDefaults' -ApplicationId $env:ApplicationID -tenantfilter $TenantFilter
                    $StateEntity = @{
                        PartitionKey       = 'AuditLogState'
                        RowKey             = "$TenantFilter-$ContentType"
                        PermissionsUpdated = $true
                        ContentType        = $ContentType
                    }
                    Add-CIPPAzDataTableEntity @AuditLogStateTable -Entity $StateEntity
                    return $true
                }

                if ($_.Exception.Message -match 'already enabled|already exists|AF20024') {
                    Write-LogMessage -API 'AuditLogIngestion' -tenant $TenantFilter -message "Subscription already exists for $ContentType" -sev Debug

                    $StateEntity = @{
                        PartitionKey        = 'AuditLogState'
                        RowKey              = $StateRowKey
                        SubscriptionEnabled = $true
                        ContentType         = $ContentType
                    }
                    Add-CIPPAzDataTableEntity @AuditLogStateTable -Entity $StateEntity -Force

                } else {
                    Write-LogMessage -API 'AuditLogIngestion' -tenant $TenantFilter -message "Failed to start subscription for $ContentType : $($_.Exception.Message)" -sev Error
                }
            }
        }

        $TotalProcessedRecords = 0
        $Now = Get-Date

        foreach ($ContentType in $ContentTypes) {
            try {
                Write-LogMessage -API 'AuditLogIngestion' -tenant $TenantFilter -message "Processing content type: $ContentType" -sev Debug

                $StateRowKey = "$TenantFilter-$ContentType"
                $StateEntity = Get-CIPPAzDataTableEntity @AuditLogStateTable -Filter "PartitionKey eq 'AuditLogState' and RowKey eq '$StateRowKey'"

                if ($StateEntity -and $StateEntity.LastContentCreatedUtc) { $StartTime = ([DateTime]$StateEntity.LastContentCreatedUtc).AddMinutes(-5).ToUniversalTime() } else { $StartTime = $Now.AddHours(-1).ToUniversalTime() }
                $EndTime = $Now.AddMinutes(-5).ToUniversalTime()
                $StartTimeStr = $StartTime.ToString('yyyy-MM-ddTHH:mm:ss.fffZ')
                $EndTimeStr = $EndTime.ToString('yyyy-MM-ddTHH:mm:ss.fffZ')
                Write-LogMessage -API 'AuditLogIngestion' -tenant $TenantFilter -message "Polling $ContentType from $StartTimeStr to $EndTimeStr" -sev Debug
                $ContentUri = "https://manage.office.com/api/v1.0/$TenantId/activity/feed/subscriptions/content?contentType=$ContentType&startTime=$StartTimeStr&endTime=$EndTimeStr"
                $ContentParams = @{
                    Uri      = $ContentUri
                    scope    = 'https://manage.office.com/.default'
                    TenantId = $TenantFilter
                }

                try {
                    $ContentList = New-GraphGetRequest @ContentParams -ErrorAction Stop
                } catch {
                    Write-LogMessage -API 'AuditLogIngestion' -tenant $TenantFilter -message "Failed to list content for $ContentType : $($_.Exception.Message)" -sev Error
                    continue
                }

                if (!$ContentList -or ($ContentList | Measure-Object).Count -eq 0) {
                    Write-LogMessage -API 'AuditLogIngestion' -tenant $TenantFilter -message "No new content available for $ContentType" -sev Debug
                    continue
                }
                Write-LogMessage -API 'AuditLogIngestion' -tenant $TenantFilter -message "Found $($ContentList.Count) content blobs for $ContentType" -sev Info
                $NewContentItems = if ($StateEntity -and $StateEntity.LastContentId) {
                    $LastContentCreated = [DateTime]$StateEntity.LastContentCreatedUtc
                    $LastContentId = $StateEntity.LastContentId

                    foreach ($Content in $ContentList) {
                        $ContentCreated = [DateTime]$Content.contentCreated
                        if ($ContentCreated -gt $LastContentCreated -or
                            ($ContentCreated -eq $LastContentCreated -and $Content.contentId -ne $LastContentId)) {
                            $Content
                        }
                    }
                } else {
                    $ContentList
                }

                if (($NewContentItems | Measure-Object).Count -eq 0) {
                    Write-LogMessage -API 'AuditLogIngestion' -tenant $TenantFilter -message "No new content items for $ContentType (all already processed)" -sev Debug
                    continue
                }

                Write-LogMessage -API 'AuditLogIngestion' -tenant $TenantFilter -message "Processing $($NewContentItems.Count) new content items for $ContentType" -sev Info

                $LatestContentCreated = $null
                $LatestContentId = $null
                $ProcessedRecords = 0

                foreach ($ContentItem in $NewContentItems) {
                    try {
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
                            continue
                        }

                        Write-LogMessage -API 'AuditLogIngestion' -tenant $TenantFilter -message "Caching $($AuditRecords.Count) audit records for $ContentType" -sev Debug

                        foreach ($Record in $AuditRecords) {
                            try {
                                $CacheEntity = @{
                                    RowKey       = $Record.Id
                                    PartitionKey = $TenantFilter
                                    JSON         = [string]($Record | ConvertTo-Json -Depth 10 -Compress)
                                    ContentId    = $ContentItem.contentId
                                    ContentType  = $ContentType
                                }
                                Add-CIPPAzDataTableEntity @CacheWebhooksTable -Entity $CacheEntity -Force
                                $ProcessedRecords++
                            } catch {
                                Write-LogMessage -API 'AuditLogIngestion' -tenant $TenantFilter -message "Failed to cache record for $ContentType : $($_.Exception.Message)" -sev Error
                            }
                        }

                        $ContentCreated = [DateTime]$ContentItem.contentCreated
                        if (!$LatestContentCreated -or $ContentCreated -gt $LatestContentCreated) {
                            $LatestContentCreated = $ContentCreated
                            $LatestContentId = $ContentItem.contentId
                        }

                    } catch {
                        Write-LogMessage -API 'AuditLogIngestion' -tenant $TenantFilter -message "Failed to download/process content blob for $ContentType : $($_.Exception.Message)" -sev Error
                        continue
                    }
                }

                Write-LogMessage -API 'AuditLogIngestion' -tenant $TenantFilter -message "Cached $ProcessedRecords audit records for $ContentType" -sev Info
                $TotalProcessedRecords += $ProcessedRecords

                $Entities = if ($LatestContentCreated) {
                    $StateEntity = @{
                        PartitionKey          = 'AuditLogState'
                        RowKey                = $StateRowKey
                        PermissionsUpdated    = $true
                        SubscriptionEnabled   = $true
                        LastContentCreatedUtc = $LatestContentCreated.ToString('yyyy-MM-ddTHH:mm:ss.fffZ')
                        LastContentId         = $LatestContentId
                        LastProcessedUtc      = $Now.ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ss.fffZ')
                        ContentType           = $ContentType
                    }

                    Write-LogMessage -API 'AuditLogIngestion' -tenant $TenantFilter -message "Updated watermark for $ContentType to $($StateEntity.LastContentCreatedUtc)" -sev Debug
                }
                Add-CIPPAzDataTableEntity @AuditLogStateTable -Entity $Entities -Force
            } catch {
                Write-LogMessage -API 'AuditLogIngestion' -tenant $TenantFilter -message "Error processing content type $ContentType : $($_.Exception.Message)" -sev Error -LogData (Get-CippException -Exception $_)
                continue
            }
        }

        Write-LogMessage -API 'AuditLogIngestion' -tenant $TenantFilter -message "Completed ingestion: $TotalProcessedRecords total records cached" -sev Info

        return $true

    } catch {
        Write-LogMessage -API 'AuditLogIngestion' -tenant $TenantFilter -message "Error ingesting audit logs: $($_.Exception.Message)" -sev Error -LogData (Get-CippException -Exception $_)
        Write-Information "Push-AuditLogIngestion: Error $($_.InvocationInfo.ScriptName) line $($_.InvocationInfo.ScriptLineNumber) - $($_.Exception.Message)"
        return $false
    }
}
