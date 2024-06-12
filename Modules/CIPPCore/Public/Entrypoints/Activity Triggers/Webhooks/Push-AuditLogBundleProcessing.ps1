function Push-AuditLogBundleProcessing {
    Param($Item)
    $TenantFilter = $Item.TenantFilter
    Write-Information "Audit log tenant filter: $TenantFilter"
    $ConfigTable = get-cipptable -TableName 'WebhookRules'
    $ConfigEntries = Get-CIPPAzDataTableEntity @ConfigTable
    #$WebhookIncoming = Get-CIPPTable -TableName 'WebhookIncoming'
    $SchedulerConfig = Get-CIPPTable -TableName 'SchedulerConfig'
    $CIPPURL = Get-CIPPAzDataTableEntity @SchedulerConfig -Filter "PartitionKey eq 'webhookcreation'" | Select-Object -First 1 -ExpandProperty CIPPURL

    $Configuration = $ConfigEntries | Where-Object { ($_.Tenants -match $TenantFilter -or $_.Tenants -match 'AllTenants') } | ForEach-Object {
        [pscustomobject]@{
            Tenants    = ($_.Tenants | ConvertFrom-Json).fullValue
            Conditions = $_.Conditions
            Actions    = $_.Actions
            LogType    = $_.Type
        }
    }

    if (($Configuration | Measure-Object).Count -eq 0) {
        Write-Information "No configuration found for tenant $TenantFilter"
        return
    }

    $LogTypes = $Configuration.LogType | Select-Object -Unique
    foreach ($LogType in $LogTypes) {
        Write-Information "Querying for log type: $LogType"
        try {
            $DataToProcess = Test-CIPPAuditLogRules -TenantFilter $TenantFilter -LogType $LogType

            Write-Information "Webhook: Data to process found: $($DataToProcess.count) items"
            foreach ($AuditLog in $DataToProcess) {
                Write-Information "Processing $($item.operation)"
                $Webhook = @{
                    Data         = $AuditLog
                    CIPPURL      = [string]$CIPPURL
                    TenantFilter = $TenantFilter
                }
                #Add-CIPPAzDataTableEntity @WebhookIncoming -Entity $Entity -Force
                #Write-Information ($AuditLog | ConvertTo-Json -Depth 10)
                Invoke-CippWebhookProcessing @Webhook
            }
        } catch {
            #Write-LogMessage -API 'Webhooks' -message 'Error processing webhooks' -sev Error -LogData (Get-CippException -Exception $_)
            Write-Host ( 'Audit log error {0} line {1} - {2}' -f $_.InvocationInfo.ScriptName, $_.InvocationInfo.ScriptLineNumber, $_.Exception.Message)
        }
    }
}