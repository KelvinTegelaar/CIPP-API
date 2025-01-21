function Get-SherwebCatalog {
    param(
        [Parameter(Mandatory = $false)]
        [string]$CustomerId,
        [string]$TenantFilter
    )
    if ($TenantFilter) {
        Get-ExtensionMapping -Extension 'Sherweb' | Where-Object { $_.RowKey -eq $TenantFilter } | ForEach-Object {
            Write-Host "Extracted customer id from tenant filter - It's $($_.IntegrationId)"
            $CustomerId = $_.IntegrationId
        }
    }
    $AuthHeader = Get-SherwebAuthentication
    $SubscriptionsList = Invoke-RestMethod -Uri "https://api.sherweb.com/service-provider/v1/customer-catalogs/$CustomerId" -Method GET -Headers $AuthHeader
    return $SubscriptionsList.catalogItems
}
