function Push-Schedulerwebhookcreation {
    <#
    .FUNCTIONALITY
        Entrypoint
    #>
    param (
        $item
    )
    <#$Table = Get-CIPPTable -TableName 'SchedulerConfig'
    $WebhookTable = Get-CIPPTable -TableName 'webhookTable'
    $Tenant = $Item.Tenant
    $Row = Get-CIPPAzDataTableEntity @Table -Filter "RowKey eq '$($item.SchedulerRow)'"
    if (!$Row) {
        Write-Information "No row found for $($item.SchedulerRow). Full received item was $($item | ConvertTo-Json)"
        return
    } else {
        Write-Information "Working on $Tenant - $($Item.Tenantid)"
        #use the queueitem to see if we already have a webhook for this tenant + webhooktype. If we do, delete this row from SchedulerConfig.
        $Webhook = Get-CIPPAzDataTableEntity @WebhookTable -Filter "PartitionKey eq '$Tenant' and Version eq '3' and Resource eq '$($Row.webhookType)'"
        if ($Webhook) {
            Write-Information "Found existing webhook for $Tenant - $($Row.webhookType)"
            if ($Row.tenantid -ne 'AllTenants') {
                Remove-AzDataTableEntity -Force @Table -Entity $Row
            }
            if (($Webhook | Measure-Object).Count -gt 1) {
                $Webhook = $Webhook | Select-Object -First 1
                $WebhooksToRemove = $ExistingWebhooks | Where-Object { $_.RowKey -ne $Webhook.RowKey }
                foreach ($RemoveWebhook in $WebhooksToRemove) {
                    Remove-AzDataTableEntity -Force @WebhookTable -Entity $RemoveWebhook
                }
            }
        } else {
            Write-Information "No existing webhook for $Tenant - $($Row.webhookType) - Time to create."
            try {
                $NewSub = New-CIPPGraphSubscription -TenantFilter $Tenant -EventType $Row.webhookType -auditLogAPI $true
                if ($NewSub.Success -and $Row.tenantid -ne 'AllTenants') {
                    Remove-AzDataTableEntity -Force @Table -Entity $Row
                } else {
                    Write-Information "Failed to create webhook for $Tenant - $($Row.webhookType) - $($_.Exception.Message)"
                }
            } catch {
                Write-Information "Failed to create webhook for $Tenant - $($Row.webhookType): $($_.Exception.Message)"
            }
        }
    }#>

}
