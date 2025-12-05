function Get-SherwebCurrentSubscription {
    param(
        [Parameter(Mandatory = $false)]
        [string]$TenantFilter,
        [string]$CustomerId,
        [string]$SKU,
        [string]$ProductName
    )
    if ($TenantFilter) {
        $TenantFilter = (Get-Tenants -TenantFilter $TenantFilter).customerId
        $CustomerId = Get-ExtensionMapping -Extension 'Sherweb' | Where-Object { $_.RowKey -eq $TenantFilter } | Select-Object -ExpandProperty IntegrationId
    }

    Write-Information "Getting current subscription for $CustomerId"
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
