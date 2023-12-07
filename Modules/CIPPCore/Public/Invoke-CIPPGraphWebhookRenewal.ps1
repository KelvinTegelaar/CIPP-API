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
            try {
                $null = New-GraphPostRequest -uri "https://graph.microsoft.com/beta/subscriptions/$($UpdateSub.SubscriptionID)" -tenantid $TenantFilter -type PATCH -body $body -Verbose
                $UpdateSub.Expiration = $RenewalDate
                $null = Add-AzDataTableEntity @WebhookTable -Entity $UpdateSub -Force
                Write-LogMessage -user 'CIPP' -API 'Renew_Graph_Subscriptions' -message "Renewed Subscription:$($UpdateSub.SubscriptionID)" -Sev "Info" -tenant $TenantFilter

            } catch {
                # Rebuild creation parameters
                $BaseURL = "$(([uri]($UpdateSub.WebhookNotificationUrl)).Host)"
                if ($UpdateSub.TypeofSubscription) {
                    $TypeofSubscription = "$($UpdateSub.TypeofSubscription)"
                } else {
                    $TypeofSubscription = 'updated'
                }
                $Resource = "$($UpdateSub.Resource)"
                $EventType = "$($UpdateSub.EventType)"

                Remove-AzDataTableEntity @WebhookTable -Entity $UpdateSub
                Write-LogMessage -user 'CIPP' -API 'Renew_Graph_Subscriptions' -message "Recreating: $($UpdateSub.SubscriptionID) as renewal failed." -Sev "Info" -tenant $TenantFilter
                
                New-CIPPGraphSubscription -TenantFilter $TenantFilter -TypeofSubscription $TypeofSubscription -BaseURL $BaseURL -Resource $Resource -EventType $EventType -ExecutingUser 'GraphSubscriptionRenewal'
            }
            

        } catch {
            Write-LogMessage -user 'CIPP' -API 'Renew_Graph_Subscriptions' -message "Failed to renew Webhook Subscription: $($UpdateSub.SubscriptionID). Linenumber: $($_.InvocationInfo.ScriptLineNumber) Error: $($_.Exception.message)" -Sev "Error" -tenant $TenantFilter
        }
    }
}
