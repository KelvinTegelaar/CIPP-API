param($Timer)

try {
    $InputObject = [PSCustomObject]@{
        OrchestratorName = 'WebhookOrchestrator'
        QueueFunction    = @{
            FunctionName = 'GetPendingWebhooks'
        }
        SkipLog          = $true
    }
    $InstanceId = Start-NewOrchestration -FunctionName 'CIPPOrchestrator' -InputObject ($InputObject | ConvertTo-Json -Depth 5)
    Write-Host "Started orchestration with ID = '$InstanceId'"
} catch {
    Write-LogMessage -API 'Webhooks' -message "Error processing webhooks - $($_.Exception.Message)" -sev Error
}
