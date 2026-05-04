function Set-Pax8Subscription {
    param(
        [Parameter(Mandatory = $false)]
        [string]$CustomerId,
        [Parameter(Mandatory = $true)]
        [string]$SKU,
        [int]$Quantity,
        [int]$Add,
        [int]$Remove,
        [string]$TenantFilter,
        [string]$BillingTerm = 'Monthly',
        $Headers
    )

    Test-Pax8LicenseRole -Headers $Headers

    if ($TenantFilter) {
        $TenantFilter = (Get-Tenants -TenantFilter $TenantFilter).customerId
        $CustomerId = Get-ExtensionMapping -Extension 'Pax8' | Where-Object { $_.RowKey -eq $TenantFilter } | Select-Object -ExpandProperty IntegrationId
    }

    if ([string]::IsNullOrWhiteSpace($CustomerId)) {
        throw 'No Pax8 mapping found'
    }

    $ExistingSubscription = Get-Pax8CurrentSubscription -CustomerId $CustomerId -SKU $SKU

    if (-not $ExistingSubscription) {
        if ($Add -or $Remove) {
            throw "Unable to Add or Remove. No existing Pax8 subscription with product ID '$SKU' found."
        }

        if (-not $Quantity -or $Quantity -le 0) {
            throw 'A valid Quantity must be specified to create a new subscription when none currently exists.'
        }

        $null = Test-Pax8OrderableProduct -ProductId $SKU
        $OrderBody = @{
            companyId  = $CustomerId
            orderedBy  = 'Pax8 Partner'
            lineItems  = @(
                @{
                    lineItemNumber = 1
                    productId      = $SKU
                    quantity       = $Quantity
                    billingTerm    = $BillingTerm
                }
            )
        }
        return Invoke-Pax8Request -Method POST -Path 'orders' -Body $OrderBody
    } else {
        $Subscription = @($ExistingSubscription)[0]
        $SubscriptionId = $Subscription.id
        $CurrentQuantity = [int]$Subscription.quantity

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

        $Body = @{
            quantity = $FinalQuantity
        }
        return Invoke-Pax8Request -Method PUT -Path "subscriptions/$SubscriptionId" -Body $Body
    }
}
