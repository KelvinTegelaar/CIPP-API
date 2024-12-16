function Remove-SherwebSubscription {
    param(
        [Parameter(Mandatory = $true)]
        [string]$CustomerId,
        [Parameter(Mandatory = $true)]
        [string[]]$SubscriptionIds
    )

    $AuthHeader = Get-SherwebAuthentication
    $Body = ConvertTo-Json -Depth 10 -InputObject @{
        subscriptionIds = $SubscriptionIds
    }

    $Uri = "https://api.sherweb.com/service-provider/v1/billing/subscriptions/cancellations?customerId=$CustomerId"
    $Cancel = Invoke-RestMethod -Uri $Uri -Method POST -Headers $AuthHeader -Body $Body -ContentType 'application/json'
    return $Cancel
}
