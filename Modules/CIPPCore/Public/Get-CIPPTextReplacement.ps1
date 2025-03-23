function Get-CIPPTextReplacement {
    <#
    .SYNOPSIS
        Replaces text with tenant specific values
    .DESCRIPTION
        Helper function to replace text with tenant specific values
    .PARAMETER TenantFilter
        The tenant filter to use
    .PARAMETER Text
        The text to replace
    .EXAMPLE
        Get-CIPPTextReplacement -TenantFilter 'contoso.com' -Text 'Hello %tenantname%'
    #>
    param (
        [string]$TenantFilter,
        $Text
    )
    if ($Text -isnot [string]) {
        return $Text
    }

    $Tenant = Get-Tenants -TenantFilter $TenantFilter
    $CustomerId = $Tenant.customerId

    #connect to table, get replacement map. The replacement map will allow users to create custom vars that get replaced by the actual values per tenant. Example:
    # %WallPaperPath% gets replaced by RowKey WallPaperPath which is set to C:\Wallpapers for tenant 1, and D:\Wallpapers for tenant 2

    # Global Variables
    $ReplaceTable = Get-CIPPTable -tablename 'CippReplacemap'
    $GlobalMap = Get-CIPPAzDataTableEntity @ReplaceTable -Filter "PartitionKey eq 'AllTenants'"
    $Vars = @{}
    if ($GlobalMap) {
        foreach ($Var in $GlobalMap) {
            $Vars[$Var.RowKey] = $Var.Value
        }
    }
    # Tenant Specific Variables
    $ReplaceMap = Get-CIPPAzDataTableEntity @ReplaceTable -Filter "PartitionKey eq '$CustomerId'"
    if ($ReplaceMap) {
        foreach ($Var in $ReplaceMap) {
            $Vars[$Var.RowKey] = $Var.Value
        }
    }
    # Replace custom variables
    foreach ($Replace in $Vars.GetEnumerator()) {
        $String = '%{0}%' -f $Replace.Key
        $Text = $Text -replace $String, $Replace.Value
    }
    #default replacements for all tenants: %tenantid% becomes $tenant.customerId, %tenantfilter% becomes $tenant.defaultDomainName, %tenantname% becomes $tenant.displayName
    $Text = $Text -replace '%tenantid%', $Tenant.customerId
    $Text = $Text -replace '%tenantfilter%', $Tenant.defaultDomainName
    $Text = $Text -replace '%tenantname%', $Tenant.displayName

    # Partner specific replacements
    $Text = $Text -replace '%partnertenantid%', $ENV:TenantID
    $Text = $Text -replace '%samappid%', $ENV:ApplicationID
    return $Text
}
