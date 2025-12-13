function Push-AuditLogIngestion {
    <#
  .FUNCTIONALITY
  Entrypoint
  #>
    param($Item)

    $TenantFilter = $Item.TenantFilter
    $TenantId = $Item.TenantId
    $ContentTypes = $Item.ContentTypes

    $Timings = @{}
    $TotalStopwatch = [System.Diagnostics.Stopwatch]::StartNew()

    try {
        if (!$ContentTypes -or $ContentTypes.Count -eq 0) {
            Write-LogMessage -API 'AuditLogIngestion' -tenant $TenantFilter -message 'No content types specified' -sev Warn
            return $true
        }

        Write-LogMessage -API 'AuditLogIngestion' -tenant $TenantFilter -message 'Starting Management API ingestion for tenant' -sev Info

        $SwInit = [System.Diagnostics.Stopwatch]::StartNew()
        $AuditLogStateTable = Get-CippTable -TableName 'AuditLogState'
        $CacheWebhooksTable = Get-CippTable -TableName 'CacheWebhooks'
        $CacheWebhooks = Get-CIPPAzDataTableEntity @CacheWebhooksTable -Filter "PartitionKey eq '$TenantFilter'"

        $SwInit.Stop()
        $Timings['Initialization'] = $SwInit.Elapsed.TotalMilliseconds

        $SwStateLoad = [System.Diagnostics.Stopwatch]::StartNew()
        $StateCache = @{}
        $StateUpdates = @{}
        foreach ($ContentType in $ContentTypes) {
            $StateRowKey = "$TenantFilter-$ContentType"
            $StateEntity = Get-CIPPAzDataTableEntity @AuditLogStateTable -Filter "PartitionKey eq 'AuditLogState' and RowKey eq '$StateRowKey'"
            $StateCache[$ContentType] = $StateEntity
        }
        $SwStateLoad.Stop()
        $Timings['StateLoad'] = $SwStateLoad.Elapsed.TotalMilliseconds

        Write-LogMessage -API 'AuditLogIngestion' -tenant $TenantFilter -message "Content types to process: $($ContentTypes -join ', ')" -sev Info

        $SwSubscriptionCheck = [System.Diagnostics.Stopwatch]::StartNew()
        $ContentTypesNeedingSubscription = [System.Collections.Generic.List[string]]::new()
        $EnabledContentTypes = [System.Collections.Generic.List[string]]::new()

        foreach ($ContentType in $ContentTypes) {
            $StateEntity = $StateCache[$ContentType]

            if ($StateEntity -and $StateEntity.SubscriptionEnabled) {
                Write-LogMessage -API 'AuditLogIngestion' -tenant $TenantFilter -message "Subscription already enabled for $ContentType" -sev Debug
                $EnabledContentTypes.Add($ContentType)
                continue
            }

            $ContentTypesNeedingSubscription.Add($ContentType)
        }
        $SwSubscriptionCheck.Stop()
        $Timings['SubscriptionCheck'] = $SwSubscriptionCheck.Elapsed.TotalMilliseconds

        $SwSubscriptionSetup = [System.Diagnostics.Stopwatch]::StartNew()
        foreach ($ContentType in $ContentTypesNeedingSubscription) {
            $StateRowKey = "$TenantFilter-$ContentType"
            $StateEntity = $StateCache[$ContentType]

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

                if (!$StateUpdates[$ContentType]) {
                    $StateUpdates[$ContentType] = @{
                        PartitionKey = 'AuditLogState'
                        RowKey       = $StateRowKey
                        ContentType  = $ContentType
                    }
                }
                $StateUpdates[$ContentType].SubscriptionEnabled = $true
                $EnabledContentTypes.Add($ContentType)

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

                    if (!$StateUpdates[$ContentType]) {
                        $StateUpdates[$ContentType] = @{
                            PartitionKey = 'AuditLogState'
                            RowKey       = $StateRowKey
                            ContentType  = $ContentType
                        }
                    }
                    $StateUpdates[$ContentType].PermissionsUpdated = $true
                    continue
                }

                if ($_.Exception.Message -match 'already enabled|already exists|AF20024') {
                    Write-LogMessage -API 'AuditLogIngestion' -tenant $TenantFilter -message "Subscription already exists for $ContentType" -sev Debug

                    if (!$StateUpdates[$ContentType]) {
                        $StateUpdates[$ContentType] = @{
                            PartitionKey = 'AuditLogState'
                            RowKey       = $StateRowKey
                            ContentType  = $ContentType
                        }
                    }
                    $StateUpdates[$ContentType].SubscriptionEnabled = $true
                    $EnabledContentTypes.Add($ContentType)

                } else {
                    Write-LogMessage -API 'AuditLogIngestion' -tenant $TenantFilter -message "Failed to start subscription for $ContentType : $($_.Exception.Message)" -sev Error
                }
            }
        }
        $SwSubscriptionSetup.Stop()
        $Timings['SubscriptionSetup'] = $SwSubscriptionSetup.Elapsed.TotalMilliseconds

        if ($EnabledContentTypes.Count -eq 0) {
            Write-LogMessage -API 'AuditLogIngestion' -tenant $TenantFilter -message 'No enabled content types to process' -sev Warn
            if ($StateUpdates.Count -gt 0) {
                $UpdateEntities = @($StateUpdates.Values)
                Add-CIPPAzDataTableEntity @AuditLogStateTable -Entity $UpdateEntities -Force
            }
            return $true
        }

        $Now = Get-Date

        # Step 1: List content for each enabled content type (sequential) WITHOUT invoking activities
        $AllContentItems = @()

        foreach ($ContentType in $EnabledContentTypes) {
            try {
                $listUri = "https://manage.office.com/api/v1.0/$TenantId/activity/feed/subscriptions/content?contentType=$ContentType"
                $params = @{
                    scope    = 'https://manage.office.com/.default'
                    Uri      = $listUri
                    TenantId = $TenantFilter
                }

                $contentPage = New-GraphGetRequest @params -ErrorAction Stop
                if ($contentPage -and $contentPage.Count -gt 0) {


                    $AllContentItems = foreach ($ci in $contentPage) {
                        if ($CacheWebhooks.ContentId -contains $ci.contentId) {
                            Write-LogMessage -API 'AuditLogIngestion' -tenant $TenantFilter -message "Content item $($ci.contentId) for $ContentType already cached, skipping" -sev Debug
                            continue
                        }
                        @{
                            FunctionName = 'AuditLogIngestionDownload'
                            TenantFilter = $TenantFilter
                            TenantId     = $TenantId
                            ContentType  = $ContentType
                            ContentItem  = $ci
                        }
                    }
                }
            } catch {
                Write-LogMessage -API 'AuditLogIngestion' -tenant $TenantFilter -message "Error listing content for $ContentType : $($_.Exception.Message)" -sev Error -LogData (Get-CippException -Exception $_)
                continue
            }
        }

        if ($AllContentItems.Count -eq 0) {
            Write-LogMessage -API 'AuditLogIngestion' -tenant $TenantFilter -message 'No content items to download' -sev Info
            if ($StateUpdates.Count -gt 0) {
                $UpdateEntities = @($StateUpdates.Values)
                Add-CIPPAzDataTableEntity @AuditLogStateTable -Entity $UpdateEntities -Force
            }
            return $true
        }

        Write-LogMessage -API 'AuditLogIngestion' -tenant $TenantFilter -message "Found $($AllContentItems.Count) total content items to process across all types" -sev Info


        $TotalStopwatch.Stop()
        # Step 2: Start NoScaling orchestrator to process items sequentially and run post-exec aggregation
        try {
            $InputObject = [PSCustomObject]@{
                OrchestratorName = 'AuditLogDownload'
                DurableMode      = 'NoScaling'
                Batch            = @($AllContentItems)
                PostExecution    = @{
                    FunctionName = 'AuditLogIngestionResults'
                    Parameters   = @{
                        TenantFilter   = $TenantFilter
                        TotalStopwatch = $TotalStopwatch.Elapsed.TotalMilliseconds
                    }
                }
                SkipLog          = $true
            }
            Start-NewOrchestration -FunctionName 'CIPPOrchestrator' -InputObject ($InputObject | ConvertTo-Json -Depth 5 -Compress)
        } catch {
            Write-LogMessage -API 'AuditLogIngestion' -tenant $TenantFilter -message "Error starting orchestrator: $($_.Exception.Message)" -sev Error -LogData (Get-CippException -Exception $_)
        }

        return $true

    } catch {
        Write-LogMessage -API 'AuditLogIngestion' -tenant $TenantFilter -message "Error ingesting audit logs: $($_.Exception.Message)" -sev Error -LogData (Get-CippException -Exception $_)
        Write-Information "Push-AuditLogIngestion: Error $($_.InvocationInfo.ScriptName) line $($_.InvocationInfo.ScriptLineNumber) - $($_.Exception.Message)"
        return $false
    }
}
