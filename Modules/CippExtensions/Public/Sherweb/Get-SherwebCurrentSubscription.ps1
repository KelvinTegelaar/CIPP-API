function Get-CurrentSherwebSubscription {
    param(
        [Parameter(Mandatory = $true)]
        [string]$CustomerId,
        [string]$SKU,
        [string]$ProductName
    )

    $AuthHeader = Get-SherwebAuthentication
    $Uri = "https://api.sherweb.com/service-provider/v1/billing/subscriptions/details?customerId=$CustomerId"
    $SubscriptionDetails = Invoke-RestMethod -Uri $Uri -Method GET -Headers $AuthHeader

    $AllSubscriptions = $SubscriptionDetails.items

    if ($SKU) {
        return $AllSubscriptions | Where-Object { $_.sku -eq $SKU }
    } elseif ($ProductName) {
        return $AllSubscriptions | Where-Object { $_.productName -eq $ProductName }
    } else {
        return $AllSubscriptions
    }
}
