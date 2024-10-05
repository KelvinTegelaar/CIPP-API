function Push-AuditLogTenant {
    Param($Item)
    $ConfigTable = Get-CippTable -TableName 'WebhookRules'
    $TenantFilter = $Item.TenantFilter

    Write-Information "Audit Logs: Processing $($TenantFilter)"

    # Get CIPP Url, cleanup legacy tasks
    $SchedulerConfig = Get-CippTable -TableName 'SchedulerConfig'
    $LegacyWebhookTasks = Get-CIPPAzDataTableEntity @SchedulerConfig -Filter "PartitionKey eq 'webhookcreation'"
    $LegacyUrl = $LegacyWebhookTasks | Select-Object -First 1 -ExpandProperty CIPPURL
    $CippConfigTable = Get-CippTable -tablename Config
    $CippConfig = Get-CIPPAzDataTableEntity @CippConfigTable -Filter "PartitionKey eq 'InstanceProperties' and RowKey eq 'CIPPURL'"
    if ($LegacyUrl) {
        if (!$CippConfig) {
            $Entity = @{
                PartitionKey = 'InstanceProperties'
                RowKey       = 'CIPPURL'
                Value        = [string]([System.Uri]$LegacyUrl).Host
            }
            Add-CIPPAzDataTableEntity @CippConfigTable -Entity $Entity -Force
        }
        # remove legacy webhooks
        foreach ($Task in $LegacyWebhookTasks) {
            Remove-AzDataTableEntity @SchedulerConfig -Entity $Task
        }
        $CIPPURL = $LegacyUrl
    } else {
        $CIPPURL = 'https://{0}' -f $CippConfig.Value
    }

    # Get webhook rules
    $ConfigEntries = Get-CIPPAzDataTableEntity @ConfigTable
    $LogSearchesTable = Get-CippTable -TableName 'AuditLogSearches'

    $Configuration = $ConfigEntries | Where-Object { ($_.Tenants -match $TenantFilter -or $_.Tenants -match 'AllTenants') }
    if ($Configuration) {
        try {
            $LogSearches = Get-CippAuditLogSearches -TenantFilter $TenantFilter -ReadyToProcess
            Write-Information ('Audit Logs: Found {0} searches, begin processing' -f $LogSearches.Count)
            foreach ($Search in $LogSearches) {
                $SearchEntity = Get-CIPPAzDataTableEntity @LogSearchesTable -Filter "Tenant eq '$($TenantFilter)' and RowKey eq '$($Search.id)'"
                $SearchEntity.CippStatus = 'Processing'
                Add-CIPPAzDataTableEntity @LogSearchesTable -Entity $SearchEntity -Force
                try {
                    # Test the audit log rules against the search results
                    $AuditLogTest = Test-CIPPAuditLogRules -TenantFilter $TenantFilter -SearchId $Search.id

                    $SearchEntity.CippStatus = 'Completed'
                    $MatchedRules = [string](ConvertTo-Json -Compress -InputObject $AuditLogTest.MatchedRules)
                    $SearchEntity | Add-Member -MemberType NoteProperty -Name MatchedRules -Value $MatchedRules -Force
                    $SearchEntity | Add-Member -MemberType NoteProperty -Name MatchedLogs -Value $AuditLogTest.MatchedLogs -Force
                    $SearchEntity | Add-Member -MemberType NoteProperty -Name TotalLogs -Value $AuditLogTest.TotalLogs -Force
                } catch {
                    $SearchEntity.CippStatus = 'Failed'
                    Write-Information "Error processing audit log rules: $($_.Exception.Message)"
                    $Exception = [string](ConvertTo-Json -Compress -InputObject (Get-CippException -Exception $_))
                    $SearchEntity | Add-Member -MemberType NoteProperty -Name Error -Value $Exception
                }
                Add-CIPPAzDataTableEntity @LogSearchesTable -Entity $SearchEntity -Force
                $DataToProcess = ($AuditLogTest).DataToProcess
                Write-Information "Audit Logs: Data to process found: $($DataToProcess.count) items"
                if ($DataToProcess) {
                    foreach ($AuditLog in $DataToProcess) {
                        Write-Information "Processing $($AuditLog.operation)"
                        $Webhook = @{
                            Data         = $AuditLog
                            CIPPURL      = [string]$CIPPURL
                            TenantFilter = $TenantFilter
                        }
                        Invoke-CippWebhookProcessing @Webhook
                    }
                }
            }
        } catch {
            Write-Information ( 'Audit Logs: Error {0} line {1} - {2}' -f $_.InvocationInfo.ScriptName, $_.InvocationInfo.ScriptLineNumber, $_.Exception.Message)
        }
    }
}
