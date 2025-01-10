function Get-SherwebCurrentSubscription {
    param(
        [Parameter(Mandatory = $false)]
        [string]$TenantFilter,
        [string]$CustomerId,
        [string]$SKU,
        [string]$ProductName
    )
if($TenantFilter){
    Get-ExtensionMapping -Extension 'Sherweb' | Where-Object { $_.RowKey -eq $TenantFilter } | ForEach-Object {
        write-host "Extracted customer id from tenant filter - It's $($_.IntegrationId)"
        $CustomerId = $_.IntegrationId
    }
}
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
