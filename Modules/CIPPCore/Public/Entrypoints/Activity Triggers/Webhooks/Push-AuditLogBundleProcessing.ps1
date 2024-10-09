function Push-AuditLogBundleProcessing {
    Param($Item)

    return # Disabled for now, as it's not used

    try {
        $AuditBundleTable = Get-CippTable -tablename 'AuditLogBundles'
        $AuditLogBundle = Get-CIPPAzDataTableEntity @AuditBundleTable -Filter "PartitionKey eq '$($Item.TenantFilter)' and RowKey eq '$($Item.ContentId)'"
        if ($AuditLogBundle.ProcessingStatus -ne 'Pending') {
            Write-Information 'Audit log bundle already processed'
            return
        }
        try {
            $AuditLogTest = Test-CIPPAuditLogRules -TenantFilter $Item.TenantFilter -LogType $AuditLogBundle.ContentType -ContentUri $AuditLogBundle.ContentUri
            $AuditLogBundle.ProcessingStatus = 'Completed'
            $AuditLogBundle.MatchedRules = [string](ConvertTo-Json -Compress -Depth 10 -InputObject $AuditLogTest.MatchedRules)
            $AuditLogBundle.MatchedLogs = $AuditLogTest.MatchedLogs
        } catch {
            $AuditLogBundle.ProcessingStatus = 'Failed'
            $AuditLogBundle | Add-Member -NotePropertyName Error -NotePropertyValue $_.InvocationInfo.PositionMessage -TypeName string
        }
        try {
            Add-CIPPAzDataTableEntity @AuditBundleTable -Entity $AuditLogBundle -Force
        } catch {
            Write-Host ( 'Error logging audit bundle: {0} line {1} - {2}' -f $_.InvocationInfo.ScriptName, $_.InvocationInfo.ScriptLineNumber, $_.Exception.Message)
        }

        $DataToProcess = ($AuditLogTest).DataToProcess
        Write-Information "Webhook: Data to process found: $($DataToProcess.count) items"
        foreach ($AuditLog in $DataToProcess) {
            Write-Information "Processing $($AuditLog.operation)"
            $Webhook = @{
                Data         = $AuditLog
                CIPPURL      = [string]$AuditLogBundle.CIPPURL
                TenantFilter = $Item.TenantFilter
            }
            Invoke-CippWebhookProcessing @Webhook
        }
    } catch {
        Write-Host ( 'Audit log error {0} line {1} - {2}' -f $_.InvocationInfo.ScriptName, $_.InvocationInfo.ScriptLineNumber, $_.Exception.Message)
    }
}
