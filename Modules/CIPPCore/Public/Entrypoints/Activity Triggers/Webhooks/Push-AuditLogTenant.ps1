function Push-AuditLogTenant {
    Param($Item)

    $AuditBundleTable = Get-CippTable -tablename 'AuditLogBundles'
    $SchedulerConfig = Get-CIPPTable -TableName 'SchedulerConfig'
    $CIPPURL = Get-CIPPAzDataTableEntity @SchedulerConfig -Filter "PartitionKey eq 'webhookcreation'" | Select-Object -First 1 -ExpandProperty CIPPURL
    $WebhookTable = Get-CippTable -tablename 'webhookTable'
    $Webhooks = Get-CIPPAzDataTableEntity @WebhookTable -Filter "PartitionKey eq '$($Item.TenantFilter)' and Version eq '3'" | Where-Object { $_.Resource -match '^Audit' }
    $ExistingBundles = Get-CIPPAzDataTableEntity @AuditBundleTable -Filter "PartitionKey eq '$($Item.TenantFilter)' and ContentType eq '$ContentType'"
    $ConfigTable = Get-CIPPTable -TableName 'WebhookRules'
    $ConfigEntries = Get-CIPPAzDataTableEntity @ConfigTable

    $NewBundles = [System.Collections.Generic.List[object]]::new()
    foreach ($Webhook in $Webhooks) {
        # only process webhooks that are configured in the webhookrules table
        $Configuration = $ConfigEntries | Where-Object { ($_.Tenants -match $TenantFilter -or $_.Tenants -match 'AllTenants') }
        if ($Configuration.Type -notcontains $Webhook.Resource) {
            continue
        }

        $TenantFilter = $Webhook.PartitionKey
        $LogType = $Webhook.Resource
        Write-Information "Querying for $LogType on $TenantFilter"
        $ContentBundleQuery = @{
            TenantFilter = $TenantFilter
            ContentType  = $LogType
            StartTime    = $Item.StartTime
            EndTime      = $Item.EndTime
        }
        $LogBundles = Get-CIPPAuditLogContentBundles @ContentBundleQuery

        foreach ($Bundle in $LogBundles) {
            if ($ExistingBundles.RowKey -notcontains $Bundle.contentId) {
                $NewBundles.Add([PSCustomObject]@{
                        PartitionKey      = $TenantFilter
                        RowKey            = $Bundle.contentId
                        DefaultDomainName = $TenantFilter
                        ContentType       = $Bundle.contentType
                        ContentUri        = $Bundle.contentUri
                        ContentCreated    = $Bundle.contentCreated
                        ContentExpiration = $Bundle.contentExpiration
                        CIPPURL           = [string]$CIPPURL
                        ProcessingStatus  = 'Pending'
                        MatchedRules      = ''
                        MatchedLogs       = 0
                    })
            }
        }
    }

    if (($NewBundles | Measure-Object).Count -gt 0) {
        Add-CIPPAzDataTableEntity @AuditBundleTable -Entity $NewBundles
        Write-Information ($NewBundles | ConvertTo-Json -Depth 5 -Compress)

        $Batch = $NewBundles | Select-Object @{Name = 'ContentId'; Expression = { $_.RowKey } }, @{Name = 'TenantFilter'; Expression = { $_.PartitionKey } }, @{Name = 'FunctionName'; Expression = { 'AuditLogBundleProcessing' } }
        $InputObject = [PSCustomObject]@{
            OrchestratorName = 'AuditLogs'
            Batch            = @($Batch)
            SkipLog          = $true
        }
        $InstanceId = Start-NewOrchestration -FunctionName 'CIPPOrchestrator' -InputObject ($InputObject | ConvertTo-Json -Depth 5 -Compress)
        Write-Host "Started orchestration with ID = '$InstanceId'"
    }

}