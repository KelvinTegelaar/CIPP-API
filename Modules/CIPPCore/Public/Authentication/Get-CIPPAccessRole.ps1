function Get-CIPPAccessRole {
    <#
    .SYNOPSIS
    Get the access role for the current user

    .DESCRIPTION
    Get the access role for the current user

    .PARAMETER TenantID
    The tenant ID to check the access role for

    .EXAMPLE
    Get-CippAccessRole -UserId $UserId

    .FUNCTIONALITY
    Internal
    #>
    [CmdletBinding()]
    param($Request)

    $CacheAccessUserRoleTable = Get-CIPPTable -tablename 'cacheAccessUserRole'
    $CachedRoles = Get-CIPPAzDataTableEntity @CacheAccessUserRoleTable -Filter "PartitionKey eq 'AccessUser' and RowKey eq '$($Request.Headers.'x-ms-client-principal-name')'" | Select-Object -ExpandProperty Role | ConvertFrom-Json

    $SwaCreds = ([System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String($request.headers.'x-ms-client-principal')) | ConvertFrom-Json)
    $SwaRoles = $SwaCreds.userRoles

    # Combine SWA roles and cached roles into a single deduplicated list
    $AllRoles = [System.Collections.Generic.List[string]]::new()
    if ($null -ne $SwaRoles) {
        $AllRoles.AddRange($SwaRoles)
    }
    if ($null -ne $CachedRoles) {
        $AllRoles.AddRange($CachedRoles)
    }

    # Remove duplicates and ensure we have a clean array
    $CombinedRoles = $AllRoles | Select-Object -Unique

    # For debugging
    Write-Information "Combined Roles: $($CombinedRoles -join ', ')"
    return $CombinedRoles
}
