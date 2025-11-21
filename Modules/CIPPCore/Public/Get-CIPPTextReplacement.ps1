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
        $Text,
        [switch]$EscapeForJson
    )
    if ($Text -isnot [string]) {
        return $Text
    }

    $ReservedVariables = @(
        '%serial%',
        '%systemroot%',
        '%systemdrive%',
        '%temp%',
        '%tenantid%',
        '%tenantfilter%',
        '%initialdomain%',
        '%tenantname%',
        '%partnertenantid%',
        '%samappid%',
        '%userprofile%',
        '%username%',
        '%userdomain%',
        '%windir%',
        '%programfiles%',
        '%programfiles(x86)%',
        '%programdata%',
        '%cippuserschema%',
        '%cippurl%',
        '%defaultdomain%',
        '%organizationid%'
    )

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
            if ($EscapeForJson.IsPresent) {
                # Escape quotes for JSON if not already escaped
                $Var.Value = $Var.Value -replace '(?<!\\)"', '\"'
            }
            $Vars[$Var.RowKey] = $Var.Value
        }
    }

    if ($Tenant) {
        # Tenant Specific Variables
        $ReplaceMap = Get-CIPPAzDataTableEntity @ReplaceTable -Filter "PartitionKey eq '$CustomerId'"
        # If no results found by customerId, try by defaultDomainName
        if (!$ReplaceMap) {
            $ReplaceMap = Get-CIPPAzDataTableEntity @ReplaceTable -Filter "PartitionKey eq '$($Tenant.defaultDomainName)'"
        }
        if ($ReplaceMap) {
            foreach ($Var in $ReplaceMap) {
                if ($EscapeForJson.IsPresent) {
                    # Escape quotes for JSON if not already escaped
                    $Var.Value = $Var.Value -replace '(?<!\\)"', '\"'
                }
                $Vars[$Var.RowKey] = $Var.Value
            }
        }
    }
    # Replace custom variables
    foreach ($Replace in $Vars.GetEnumerator()) {
        $String = '%{0}%' -f $Replace.Key
        if ($string -notin $ReservedVariables) {
            $Text = $Text -replace $String, $Replace.Value
        }
    }
    #default replacements for all tenants: %tenantid% becomes $tenant.customerId, %tenantfilter% becomes $tenant.defaultDomainName, %tenantname% becomes $tenant.displayName
    $Text = $Text -replace '%tenantid%', $Tenant.customerId
    $Text = $Text -replace '%organizationid%', $Tenant.customerId
    $Text = $Text -replace '%tenantfilter%', $Tenant.defaultDomainName
    $Text = $Text -replace '%defaultdomain%', $Tenant.defaultDomainName
    $Text = $Text -replace '%initialdomain%', $Tenant.initialDomainName
    $Text = $Text -replace '%tenantname%', $Tenant.displayName

    # Partner specific replacements
    $Text = $Text -replace '%partnertenantid%', $env:TenantID
    $Text = $Text -replace '%samappid%', $env:ApplicationID

    if ($Text -match '%cippuserschema%') {
        $Schema = Get-CIPPSchemaExtensions | Where-Object { $_.id -match '_cippUser' } | Select-Object -First 1
        $Text = $Text -replace '%cippuserschema%', $Schema.id
    }

    if ($Text -match '%cippurl%') {
        $ConfigTable = Get-CIPPTable -tablename 'Config'
        $Config = Get-CIPPAzDataTableEntity @ConfigTable -Filter "PartitionKey eq 'InstanceProperties' and RowKey eq 'CIPPURL'"
        if ($Config) {
            $Text = $Text -replace '%cippurl%', $Config.Value
        }
    }
    return $Text
}
