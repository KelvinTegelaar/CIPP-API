function Set-CIPPGraphSubscription {
    [CmdletBinding()]
    param (
        $TenantFilter,
        $RenewSubscriptions,
        $Resource,
        $EventType,
        $APIName = 'Set Graph Webhook',
        $Headers
    )

    if ($RenewSubscriptions) {
        $RenewalDate = (Get-Date).AddDays(1).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ss.fffZ')
        $body = @{
            'expirationDateTime' = "$RenewalDate"
        } | ConvertTo-Json
        $null = (New-GraphGetRequest -uri 'https://graph.microsoft.com/beta/subscriptions' -tenantid $TenantFilter) | ForEach-Object {
            try {
                $GraphRequest = New-GraphPostRequest -uri "https://graph.microsoft.com/beta/subscriptions/$($_.id)" -tenantid $TenantFilter -type PATCH -body $body -Verbose
                $WebhookTable = Get-CIPPTable -TableName webhookTable
                #get the row from the table, grab it by the webhook notification url, and update the expiration date.
                $WebhookRow = Get-CIPPAzDataTableEntity @WebhookTable | Where-Object { $_.WebhookNotificationUrl -eq $GraphRequest.notificationUrl }
                $WebhookRow.Expiration = $RenewalDate
                $null = Add-CIPPAzDataTableEntity @WebhookTable -Entity $WebhookRow -Force
                return "Renewed $($GraphRequest.notificationUrl)"

            } catch {
                $ErrorMessage = Get-CippException -Exception $_
                Write-LogMessage -headers $Headers -API $APIName -message "Failed to renew Webhook Subscription: $($ErrorMessage.NormalizedError)" -Sev 'Error' -tenant $TenantFilter -LogData $ErrorMessage
                return   "Failed to renew Webhook Subscription $($WebhookRow.RowKey): $($ErrorMessage.NormalizedError)"
            }
        }
    }
}
