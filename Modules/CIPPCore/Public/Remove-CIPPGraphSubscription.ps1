function Remove-CIPPGraphSubscription {
    [CmdletBinding()]
    param (
        $TenantFilter,
        $CIPPID,
        $APIName = 'Remove Graph Webhook',
        $Type,
        $ExecutingUser
    )
    try {
        $WebhookTable = Get-CIPPTable -TableName webhookTable
        if ($type -eq 'AuditLog') {
            $WebhookRow = Get-CIPPAzDataTableEntity @WebhookTable | Where-Object { $_.PartitionKey -eq $TenantFilter }
        } else {
            $WebhookRow = Get-CIPPAzDataTableEntity @WebhookTable | Where-Object { $_.RowKey -eq $CIPPID }
        }
        $Entity = $WebhookRow | Select-Object PartitionKey, RowKey
        if ($Type -eq 'AuditLog') {
            try {
                foreach ($EventType in $WebhookRow.EventType) {
                    $AuditLog = New-GraphPOSTRequest -uri "https://manage.office.com/api/v1.0/$($TenantFilter)/activity/feed/subscriptions/stop?contentType=$($EventType)" -scope 'https://manage.office.com/.default' -tenantid $TenantFilter -type POST -body '{}' -verbose
                }            
            } catch {
                Write-LogMessage -user $ExecutingUser -API $APIName -message "Failed to remove webhook subscription at Microsoft's side: $($_.Exception.Message)" -Sev 'Error' -tenant $TenantFilter
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