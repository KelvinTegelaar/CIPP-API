function Push-PublicWebhookProcess {
    param($Item)

    try {
        if ($Item.Type -eq 'GraphSubscription') {
            Invoke-CippGraphWebhookProcessing -Data ($Item.Data | ConvertFrom-Json) -CIPPID $Item.CIPPID -WebhookInfo ($Item.Webhookinfo | ConvertFrom-Json)
        } elseif ($Item.Type -eq 'AuditLog') {
            Invoke-CippWebhookProcessing -TenantFilter $Item.TenantFilter -Data ($Item.Data | ConvertFrom-Json) -CIPPPURL $Item.CIPPURL
        }
        $WebhookIncoming = Get-CIPPTable -TableName WebhookIncoming
        $Entity = $Item | Select-Object -Property RowKey, PartitionKey
        Remove-AzDataTableEntity @WebhookIncoming -Entity $Entity
    } catch {
        Write-Host "Webhook Exception: $($_.Exception.Message)"
    }

}