function Remove-SherwebSubscription {
    param(
        [Parameter(Mandatory = $false)]
        [string]$CustomerId,
        [Parameter(Mandatory = $true)]
        [string[]]$SubscriptionIds,
        [string]$TenantFilter
    )
    if ($TenantFilter) {
        Get-ExtensionMapping -Extension 'Sherweb' | Where-Object { $_.RowKey -eq $TenantFilter } | ForEach-Object {
            Write-Host "Extracted customer id from tenant filter - It's $($_.IntegrationId)"
            $CustomerId = $_.IntegrationId
        }
    }
    $AuthHeader = Get-SherwebAuthentication
    $Body = ConvertTo-Json -Depth 10 -InputObject @{
        subscriptionIds = @($SubscriptionIds)
    }

    $Uri = "https://api.sherweb.com/service-provider/v1/billing/subscriptions/cancellations?customerId=$CustomerId"
    $Cancel = Invoke-RestMethod -Uri $Uri -Method POST -Headers $AuthHeader -Body $Body -ContentType 'application/json'
    return $Cancel
}
