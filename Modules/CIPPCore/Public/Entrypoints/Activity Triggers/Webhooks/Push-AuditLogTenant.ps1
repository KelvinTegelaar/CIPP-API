function Push-AuditLogTenant {
    Param($Item)

    $SchedulerConfig = Get-CippTable -TableName 'SchedulerConfig'
    $ConfigTable = Get-CippTable -TableName 'WebhookRules'
    #$Tenant = Get-Tenants -TenantFilter $Item.customerId -IncludeErrors
    $TenantFilter = $Item.TenantFilter

    Write-Information "Audit Logs: Processing $($TenantFilter)"
    # Query CIPPURL for linking
    $CIPPURL = Get-CIPPAzDataTableEntity @SchedulerConfig -Filter "PartitionKey eq 'webhookcreation'" | Select-Object -First 1 -ExpandProperty CIPPURL

    # Get webhook rules
    $ConfigEntries = Get-CIPPAzDataTableEntity @ConfigTable
    $LogSearchesTable = Get-CippTable -TableName 'AuditLogSearches'

    $Configuration = $ConfigEntries | Where-Object { ($_.Tenants -match $TenantFilter -or $_.Tenants -match 'AllTenants') }
    if ($Configuration) {
        try {
            $LogSearches = Get-CippAuditLogSearches -TenantFilter $TenantFilter -ReadyToProcess
            Write-Information ('Audit Logs: Found {0} searches, begin processing' -f $LogSearches.Count)
            foreach ($Search in $LogSearches) {
                $SearchEntity = Get-CIPPAzDataTableEntity @LogSearchesTable -Filter "PartitionKey eq '$($TenantFilter)' and RowKey eq '$($Search.id)'"
                $SearchEntity.CippStatus = 'Processing'
                Add-CIPPAzDataTableEntity @LogSearchesTable -Entity $SearchEntity -Force
                try {
                    # Test the audit log rules against the search results
                    $AuditLogTest = Test-CIPPAuditLogRules -TenantFilter $TenantFilter -SearchId $Search.id

                    $SearchEntity.CippStatus = 'Completed'
                    $SearchEntity | Add-Member -MemberType NoteProperty -Name MatchedRules -Value [string](ConvertTo-Json -Compress -Depth 10 -InputObject $AuditLogTest.MatchedRules)
                    $SearchEntity | Add-Member -MemberType NoteProperty -Name MatchedLogs -Value $AuditLogTest.MatchedLogs
                    $SearchEntity | Add-Member -MemberType NoteProperty -Name TotalLogs -Value $AuditLogTest.TotalLogs
                } catch {
                    $SearchEntity.CippStatus = 'Failed'
                    $SearchEntity | Add-Member -MemberType NoteProperty -Name Error -Value $_.InvocationInfo.PositionMessage
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
