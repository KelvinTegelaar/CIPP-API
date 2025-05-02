function Set-CIPPSherwebLicense {
    param (
        [Parameter(Mandatory = $true)]
        [string]$tenantFilter,

        [Parameter(Mandatory = $true)]
        [string]$SKUid,

        [int]$Quantity,
        [int]$Add,
        [int]$Remove
    )

    Set-SherwebSubscription -SKU $SKUid -Quantity $Quantity -Add $Add -Remove $Remove -TenantFilter $tenantFilter
}
