function Set-SherwebSubscription {
    param(
        [Parameter(Mandatory = $false)]
        [string]$CustomerId,
        [Parameter(Mandatory = $true)]
        [string]$SKU,
        [int]$Quantity,
        [int]$Add,
        [int]$Remove,
        [string]$TenantFilter
    )
    if ($TenantFilter) {
        $TenantFilter = (Get-Tenants -TenantFilter $TenantFilter).customerId
        $CustomerId = Get-ExtensionMapping -Extension 'Sherweb' | Where-Object { $_.RowKey -eq $TenantFilter } | Select-Object -ExpandProperty IntegrationId
    }
    $AuthHeader = Get-SherwebAuthentication
    $ExistingSubscription = Get-SherwebCurrentSubscription -CustomerId $CustomerId -SKU $SKU

    if (-not $ExistingSubscription) {
        if ($Add -or $Remove) {
            throw "Unable to Add or Remove. No existing subscription with SKU '$SKU' found."
        }

        if (-not $Quantity -or $Quantity -le 0) {
            throw 'A valid Quantity must be specified to create a new subscription when none currently exists.'
        }
        $OrderBody = ConvertTo-Json -Depth 10 -InputObject @{
            cartItems = @(
                @{
                    sku      = $SKU
                    quantity = $Quantity
                }
            )
            orderedBy = 'CIPP-API'
        }
        $OrderUri = "https://api.sherweb.com/service-provider/v1/orders?customerId=$CustomerId"
        $Order = Invoke-RestMethod -Uri $OrderUri -Method POST -Headers $AuthHeader -Body $OrderBody -ContentType 'application/json'
        return $Order

    } else {
        $SubscriptionId = $ExistingSubscription[0].id
        $CurrentQuantity = $ExistingSubscription[0].quantity

        if ($Add) {
            $FinalQuantity = $CurrentQuantity + $Add
        } elseif ($Remove) {
            $FinalQuantity = $CurrentQuantity - $Remove
            if ($FinalQuantity -lt 0) {
                throw "Cannot remove more licenses than currently allocated. Current: $CurrentQuantity, Attempting to remove: $Remove."
            }
        } else {
            if (-not $Quantity -or $Quantity -le 0) {
                throw 'A valid Quantity must be specified if Add/Remove are not used.'
            }
            $FinalQuantity = $Quantity
        }
        $Body = ConvertTo-Json -Depth 10 -InputObject @{
            subscriptionAmendmentParameters = @(
                @{
                    subscriptionId = $SubscriptionId
                    newQuantity    = $FinalQuantity
                }
            )
        }
        $Uri = "https://api.sherweb.com/service-provider/v1/billing/subscriptions/amendments?customerId=$CustomerId"
        $Update = Invoke-RestMethod -Uri $Uri -Method POST -Headers $AuthHeader -Body $Body -ContentType 'application/json'
        return $Update
    }
}
