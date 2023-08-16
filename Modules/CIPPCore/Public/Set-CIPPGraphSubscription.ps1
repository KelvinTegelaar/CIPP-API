function Set-CIPPGraphSubscription {
    [CmdletBinding()]
    param (
        $TenantFilter,
        $RenewSubscriptions,
        $Resource,
        $EventType,
        $APIName = "Set Graph Webhook",
        $ExecutingUser
    )

    if ($RenewSubscriptions) {
        $RenewalDate = (Get-Date).AddDays(1).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ss.fffZ")
        $body = @{
            "expirationDateTime" = "$RenewalDate"
        } | ConvertTo-Json
        $ExistingSub = (New-GraphGetRequest -uri "https://graph.microsoft.com/beta/subscriptions" -tenantid $TenantFilter) | ForEach-Object {
            try {
                $GraphRequest = New-GraphPostRequest -uri "https://graph.microsoft.com/beta/subscriptions/$($_.id)" -tenantid $TenantFilter -type PATCH -body $body -Verbose
                $WebhookTable = Get-CIPPTable -TableName webhookTable
                #get the row from the table, grab it by the webhook notification url, and update the expiration date.
                $WebhookRow = Get-AzDataTableEntity @WebhookTable | Where-Object { $_.WebhookNotificationUrl -eq $GraphRequest.notificationUrl }
                $WebhookRow.Expiration = $RenewalDate
                $null = Add-AzDataTableEntity @WebhookTable -Entity $WebhookRow -Force
                return "Renewed $($GraphRequest.notificationUrl)" 

            }
            catch {
                Write-LogMessage -user $ExecutingUser -API $APIName -message "Failed to renew Webhook Subscription: $($_.Exception.Message)" -Sev "Error" -tenant $TenantFilter
                return   "Failed to renew Webhook Subscription $($WebhookRow.RowKey): $($_.Exception.Message)" 
            }
        }
    }
}