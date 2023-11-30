function Invoke-CippGraphWebhookRenewal {
    $RenewalDate = (Get-Date).AddDays(1).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ss.fffZ")
    $body = @{
        "expirationDateTime" = "$RenewalDate"
    } | ConvertTo-Json


    $WebhookTable = Get-CIPPTable -TableName webhookTable
    $WebhookData = Get-AzDataTableEntity @WebhookTable | Where-Object { $null -ne $_.SubscriptionID -and $_.SubscriptionID -ne '' -and ((Get-Date($_.Expiration)) -le ((Get-Date).AddHours(2))) }

    foreach ($UpdateSub in $WebhookData) {
        try {
            $TenantFilter = $UpdateSub.PartitionKey
            $null = New-GraphPostRequest -uri "https://graph.microsoft.com/beta/subscriptions/$($UpdateSub.SubscriptionID)" -tenantid $TenantFilter -type PATCH -body $body -Verbose
            $UpdateSub.Expiration = $RenewalDate
            $null = Add-AzDataTableEntity @WebhookTable -Entity $UpdateSub -Force
            Write-LogMessage -user 'CIPP' -API 'Renew_Graph_Subscriptions' -message "Renewed Subscription:$($UpdateSub.SubscriptionID)" -Sev "Info" -tenant $TenantFilter

        } catch {
            Write-LogMessage -user 'CIPP' -API 'Renew_Graph_Subscriptions' -message "Failed to renew Webhook Subscription: $($UpdateSub.SubscriptionID)" -Sev "Error" -tenant $TenantFilter
        }
    }
}
