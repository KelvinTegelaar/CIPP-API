function Get-Pax8Catalog {
    param(
        [Parameter(Mandatory = $false)]
        [string]$CustomerId,
        [string]$TenantFilter
    )

    if ($TenantFilter) {
        $TenantFilter = (Get-Tenants -TenantFilter $TenantFilter).customerId
        $CustomerId = Get-ExtensionMapping -Extension 'Pax8' | Where-Object { $_.RowKey -eq $TenantFilter } | Select-Object -ExpandProperty IntegrationId
    }

    if ([string]::IsNullOrWhiteSpace($CustomerId)) {
        throw 'No Pax8 mapping found'
    }

    Write-Information "Getting Pax8 catalog for $CustomerId"
    $Products = Get-Pax8PagedData -Path 'products' -Query @{ vendorName = 'Microsoft' }
    return @($Products | ForEach-Object {
            $ProductName = $_.name ?? $_.displayName
            [PSCustomObject]@{
                id             = $_.id
                sku            = $_.id
                productId      = $_.id
                name           = @(@{ value = $ProductName })
                productName    = $ProductName
                vendorName     = $_.vendorName ?? $_.vendor
                billingCycle   = $_.billingTerm ?? $_.billingCycle ?? 'Monthly'
                billingTerm    = $_.billingTerm ?? $_.billingCycle ?? 'Monthly'
                commitmentTerm = $_.commitmentTerm ?? $_.term
                description    = @(@{ value = $_.description })
            }
        })
}
