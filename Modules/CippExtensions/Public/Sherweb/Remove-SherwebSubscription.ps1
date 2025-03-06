function Remove-SherwebSubscription {
    param(
        [Parameter(Mandatory = $false)]
        [string]$CustomerId,
        [Parameter(Mandatory = $true)]
        [string[]]$SubscriptionIds,
        [string]$TenantFilter
    )
    if ($TenantFilter) {
        $TenantFilter = (Get-Tenants -TenantFilter $TenantFilter).customerId
        $CustomerId = Get-ExtensionMapping -Extension 'Sherweb' | Where-Object { $_.RowKey -eq $TenantFilter } | Select-Object -ExpandProperty IntegrationId
    }
    $AuthHeader = Get-SherwebAuthentication
    $Body = ConvertTo-Json -Depth 10 -InputObject @{
        subscriptionIds = @($SubscriptionIds)
    }

    $Uri = "https://api.sherweb.com/service-provider/v1/billing/subscriptions/cancellations?customerId=$CustomerId"
    $Cancel = Invoke-RestMethod -Uri $Uri -Method POST -Headers $AuthHeader -Body $Body -ContentType 'application/json'
    return $Cancel
}
