function Start-WebhookOrchestrator {
    <#
    .SYNOPSIS
    Start the Webhook Orchestrator
    #>
    [CmdletBinding(SupportsShouldProcess = $true)]
    param()
    try {
        $webhookTable = Get-CIPPTable -tablename webhookTable
        $Webhooks = Get-CIPPAzDataTableEntity @webhookTable -Property PartitionKey, RowKey
        if (($Webhooks | Measure-Object).Count -eq 0) {
            Write-Information 'No webhook subscriptions found. Exiting.'
            return
        }

        $WebhookIncomingTable = Get-CIPPTable -TableName WebhookIncoming
        $WebhookIncoming = Get-CIPPAzDataTableEntity @WebhookIncomingTable -Property PartitionKey, RowKey
        if (($WebhookIncoming | Measure-Object).Count -eq 0) {
            Write-Information 'No webhook incoming found. Exiting.'
            return
        }

        Write-Information 'Processing webhooks'

        $InputObject = [PSCustomObject]@{
            OrchestratorName = 'WebhookOrchestrator'
            QueueFunction    = @{
                FunctionName = 'GetPendingWebhooks'
            }
            SkipLog          = $true
        }
        if ($PSCmdlet.ShouldProcess('Start-WebhookOrchestrator', 'Starting Webhook Orchestrator')) {
            Start-NewOrchestration -FunctionName 'CIPPOrchestrator' -InputObject ($InputObject | ConvertTo-Json -Depth 5 -Compress)

        }
    } catch {
        Write-LogMessage -API 'Webhooks' -message 'Error processing webhooks' -sev Error -LogData (Get-CippException -Exception $_)
        Write-Information ( 'Webhook error {0} line {1} - {2}' -f $_.InvocationInfo.ScriptName, $_.InvocationInfo.ScriptLineNumber, $_.Exception.Message)
    }
}
