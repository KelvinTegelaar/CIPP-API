function Get-SherwebCatalog {
    param(
        [Parameter(Mandatory = $false)]
        [string]$CustomerId,
        [string]$TenantFilter
    )

    if ($TenantFilter) {
        $TenantFilter = (Get-Tenants -TenantFilter $TenantFilter).customerId
        $CustomerId = Get-ExtensionMapping -Extension 'Sherweb' | Where-Object { $_.RowKey -eq $TenantFilter } | Select-Object -ExpandProperty IntegrationId
    }

    if (![string]::IsNullOrEmpty($CustomerId)) {
        Write-Information "Getting catalog for $CustomerId"
        $AuthHeader = Get-SherwebAuthentication
        $SubscriptionsList = Invoke-RestMethod -Uri "https://api.sherweb.com/service-provider/v1/customer-catalogs/$CustomerId" -Method GET -Headers $AuthHeader
        return $SubscriptionsList.catalogItems
    } else {
        throw 'No Sherweb mapping found'
    }
}
