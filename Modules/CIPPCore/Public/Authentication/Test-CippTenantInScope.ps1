function Test-CippTenantInScope {
    <#
    .SYNOPSIS
        True when every tenant a stored row targets is in the caller's request scope.
    .DESCRIPTION
        For endpoints that act on a stored row by its key, where the router never saw the row's tenant.
        Takes domains, customerIds or tenant selector objects ({ value; type }). All Tenants and tenant
        groups only pass for an unrestricted caller. Must live in CIPPCore, next to the scope slot.
    .FUNCTIONALITY
        Internal
    #>
    [CmdletBinding()]
    param(
        [AllowNull()][AllowEmptyCollection()]$Tenant
    )
    $Rows = @(foreach ($Item in @($Tenant)) {
            $Value = $Item.value ?? $Item
            if ($Value) { [pscustomobject]@{ Tenant = "$Value" } }
        })
    @($Rows | Select-CippAllowedTenantData).Count -eq $Rows.Count
}
