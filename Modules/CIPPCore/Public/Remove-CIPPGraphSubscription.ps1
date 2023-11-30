function Remove-CIPPGraphSubscription {
    [CmdletBinding()]
    param (
        $TenantFilter,
        $CIPPID,
        $APIName = 'Remove Graph Webhook',
        $ExecutingUser
    )
    try {
        $WebhookTable = Get-CIPPTable -TableName webhookTable
        $WebhookRow = Get-CIPPAzDataTableEntity @WebhookTable | Where-Object { $_.RowKey -eq $CIPPID }
        $Entity = $WebhookRow | Select-Object PartitionKey, RowKey
        if ($WebhookRow.Resource -eq 'M365AuditLogs') {
            try {
                $AuditLog = New-GraphPOSTRequest -uri "https://manage.office.com/api/v1.0/$($TenantFilter)/activity/feed/subscriptions/stop?contentType=$($WebhookRow.EventType)" -scope 'https://manage.office.com/.default' -tenantid $TenantFilter -type POST -body '{}' -verbose
            } catch {
                #allowed to fail if the subscription is already removed
            }
            $null = Remove-AzDataTableEntity @WebhookTable -Entity $Entity
        } else {
            $OldID = (New-GraphGetRequest -uri 'https://graph.microsoft.com/beta/subscriptions' -tenantid $TenantFilter) | Where-Object { $_.notificationUrl -eq $WebhookRow.WebhookNotificationUrl }
            $GraphRequest = New-GraphPostRequest -uri "https://graph.microsoft.com/beta/subscriptions/$($oldId.ID)" -tenantid $TenantFilter -type DELETE -body {} -Verbose
            $null = Remove-AzDataTableEntity @WebhookTable -Entity $Entity
        }
        return "Removed webhook subscription to $($WebhookRow.resource) for $($TenantFilter)"

    } catch {
        Write-LogMessage -user $ExecutingUser -API $APIName -message "Failed to renew Webhook Subscription: $($_.Exception.Message)" -Sev 'Error' -tenant $TenantFilter
        return "Failed to remove Webhook Subscription $($GraphRequest.value.notificationUrl): $($_.Exception.Message)"
    }
}