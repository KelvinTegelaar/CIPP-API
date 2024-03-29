function Push-GetPendingWebhooks {
    $Table = Get-CIPPTable -TableName WebhookIncoming
    $Webhooks = Get-CIPPAzDataTableEntity @Table
    $WebhookCount = ($Webhooks | Measure-Object).Count
    $Message = 'Processing {0} webhooks' -f $WebhookCount
    Write-LogMessage -API 'Webhooks' -message $Message -sev Info
    return $Webhooks
}