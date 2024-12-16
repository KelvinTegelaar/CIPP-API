function Get-SherwebCatalog {
    param(
        [Parameter(Mandatory = $true)]
        [string]$CustomerId
    )

    $AuthHeader = Get-SherwebAuthentication
    $SubscriptionsList = Invoke-RestMethod -Uri "https://api.sherweb.com/service-provider/v1/customer-catalogs/$CustomerId" -Method GET -Headers $AuthHeader
    return $SubscriptionsList.catalogItems
}
