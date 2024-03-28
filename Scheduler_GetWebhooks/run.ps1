param($Timer)

$Table = Get-CIPPTable -TableName WebhookIncoming
$Webhooks = Get-CIPPAzDataTableEntity @Table
$WebhookCount = ($Webhooks | Measure-Object).Count
$Message = 'Processing {0} webhooks' -f $WebhookCount
Write-LogMessage -API 'Webhooks' -message $Message -sev Info

try {
    for ($i = 0; $i -lt $WebhookCount; $i += 2500) {
        $WebhookBatch = $Webhooks[$i..($i + 2499)]
        $InputObject = [PSCustomObject]@{
            OrchestratorName = 'WebhookOrchestrator'
            Batch            = @($WebhookBatch)
            SkipLog          = $true
        }
        #Write-Host ($InputObject | ConvertTo-Json)
        $InstanceId = Start-NewOrchestration -FunctionName 'CIPPOrchestrator' -InputObject ($InputObject | ConvertTo-Json -Depth 5)
        Write-Host "Started orchestration with ID = '$InstanceId'"
    }
} catch {
    Write-LogMessage -API 'Webhooks' -message "Error processing webhooks - $($_.Exception.Message)" -sev Error
} finally {
    Write-LogMessage -API 'Webhooks' -message 'Webhook processing completed' -sev Info
}
