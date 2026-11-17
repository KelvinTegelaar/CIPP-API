function Set-ExternalCSPSubscription {
    <#
    .FUNCTIONALITY
        Internal
    .DESCRIPTION
        Buys a new subscription, or changes the quantity of an existing one, through the External CSP integration.
        -Add and -Remove are relative to the current quantity; -Quantity is absolute. The vendor always receives the new absolute quantity.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$SKU,
        [int]$Quantity,
        [int]$Add,
        [int]$Remove,
        [Parameter(Mandatory = $true)]
        [string]$TenantFilter,
        $Headers
    )

    $Existing = @(Invoke-ExternalCSPRequest -Action Subscriptions -TenantFilter $TenantFilter) | Where-Object { $_.sku -eq $SKU } | Select-Object -First 1

    if (-not $Existing) {
        if ($Add -or $Remove) {
            throw "Unable to Add or Remove. No existing subscription with SKU '$SKU' found."
        }
        if ($Quantity -le 0) {
            throw 'A valid Quantity must be specified to create a new subscription when none currently exists.'
        }
        return Invoke-ExternalCSPRequest -Action Order -TenantFilter $TenantFilter -Headers $Headers -Body @{
            sku       = $SKU
            quantity  = $Quantity
            orderedBy = 'CIPP'
        }
    }

    $CurrentQuantity = [int]$Existing.quantity
    if ($Add) {
        $FinalQuantity = $CurrentQuantity + $Add
    } elseif ($Remove) {
        $FinalQuantity = $CurrentQuantity - $Remove
    } else {
        $FinalQuantity = $Quantity
    }
    if ($FinalQuantity -lt 1) {
        throw "The resulting quantity must be at least 1 (current: $CurrentQuantity, requested: $FinalQuantity). Cancel the subscription to remove it entirely."
    }

    return Invoke-ExternalCSPRequest -Action Quantity -TenantFilter $TenantFilter -Headers $Headers -Body @{
        subscriptionId = $Existing.subscriptionId
        sku            = $SKU
        quantity       = $FinalQuantity
    }
}
