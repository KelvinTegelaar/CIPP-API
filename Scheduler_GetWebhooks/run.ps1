param($Timer)

try {

    $webhookTable = Get-CIPPTable -tablename webhookTable
    $Webhooks = Get-CIPPAzDataTableEntity @webhookTable -Property RowKey
    if (($Webhooks | Measure-Object).Count -eq 0) {
        Write-Host 'No webhook subscriptions found. Exiting.'
        return
    }
    Write-Host 'Processing webhooks'

    $InputObject = [PSCustomObject]@{
        OrchestratorName = 'WebhookOrchestrator'
        QueueFunction    = @{
            FunctionName = 'GetPendingWebhooks'
        }
        SkipLog          = $true
    }
    Write-Host ($InputObject | ConvertTo-Json -Depth 5)
    $InstanceId = Start-NewOrchestration -FunctionName 'CIPPOrchestrator' -InputObject ($InputObject | ConvertTo-Json -Depth 5 -Compress)
    Write-Host "Started orchestration with ID = '$InstanceId'"
} catch {
    Write-LogMessage -API 'Webhooks' -message 'Error processing webhooks' -sev Error -LogData (Get-CippException -Exception $_)
    Write-Host ( 'Webhook error {0} line {1} - {2}' -f $_.InvocationInfo.ScriptName, $_.InvocationInfo.ScriptLineNumber, $_.Exception.Message)
}
