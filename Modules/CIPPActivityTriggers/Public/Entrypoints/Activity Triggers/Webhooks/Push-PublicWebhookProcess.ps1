function Push-PublicWebhookProcess {
    <#
    .FUNCTIONALITY
        Entrypoint
    #>
    param($Item)

    $Table = Get-CIPPTable -TableName WebhookIncoming
    $Webhook = Get-CIPPAzDataTableEntity @Table -Filter "RowKey eq '$($Item.RowKey)'"
    try {
        if ($Webhook.Type -eq 'GraphSubscription') {
            Invoke-CippGraphWebhookProcessing -Data ($Webhook.Data | ConvertFrom-Json) -CIPPID $Webhook.CIPPID -WebhookInfo ($Webhook.Webhookinfo | ConvertFrom-Json)
        } elseif ($Webhook.Type -eq 'AuditLog') {
            Invoke-CippWebhookProcessing -TenantFilter $Webhook.TenantFilter -Data ($Webhook.Data | ConvertFrom-Json) -CIPPURL $Webhook.CIPPURL
        } elseif ($Webhook.Type -eq 'PartnerCenter') {
            Invoke-CippPartnerWebhookProcessing -Data ($Webhook.Data | ConvertFrom-Json)
        }
    } catch {
        Write-Host "Webhook Exception: $($_.Exception.Message)"
    } finally {
        $Entity = $Webhook | Select-Object -Property RowKey, PartitionKey
        Remove-AzDataTableEntity -Force @Table -Entity $Entity
    }
}
