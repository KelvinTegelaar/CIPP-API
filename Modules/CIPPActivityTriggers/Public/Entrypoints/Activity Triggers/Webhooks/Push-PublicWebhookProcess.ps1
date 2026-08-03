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
        if ($Webhook) {
            try {
                $Entity = $Webhook | Select-Object -Property RowKey, PartitionKey
                Remove-CIPPAzDataTableEntity -Force @Table -Entity $Entity
            } catch {
                # Row may have already been deleted by a concurrent execution - this is expected
                Write-Information "Webhook cleanup for RowKey '$($Item.RowKey)': $($_.Exception.Message)"
            }
        } else {
            Write-Warning "Webhook row not found for RowKey '$($Item.RowKey)' - skipping cleanup"
        }
    }
}
