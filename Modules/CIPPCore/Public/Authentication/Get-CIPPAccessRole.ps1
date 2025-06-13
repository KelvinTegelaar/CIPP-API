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
    param($Request, $Headers)

    $Headers = $Request.Headers ?? $Headers

    $CacheAccessUserRoleTable = Get-CIPPTable -tablename 'cacheAccessUserRoles'

    $SwaCreds = ([System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String($Headers.'x-ms-client-principal')) | ConvertFrom-Json)
    $SwaRoles = $SwaCreds.userRoles
    $Username = $SwaCreds.userDetails

    $CachedRoles = Get-CIPPAzDataTableEntity @CacheAccessUserRoleTable -Filter "PartitionKey eq 'AccessUser' and RowKey eq '$Username'" | Select-Object -ExpandProperty Role | ConvertFrom-Json

    Write-Information "SWA Roles: $($SwaRoles -join ', ')"
    Write-Information "Cached Roles: $($CachedRoles -join ', ')"

    # Combine SWA roles and cached roles into a single deduplicated list
    $AllRoles = [System.Collections.Generic.List[string]]::new()

    foreach ($Role in $SwaRoles) {
        if (-not $AllRoles.Contains($Role)) {
            $AllRoles.Add($Role)
        }
    }
    foreach ($Role in $CachedRoles) {
        if (-not $AllRoles.Contains($Role)) {
            $AllRoles.Add($Role)
        }
    }
    $CombinedRoles = $AllRoles | Select-Object -Unique

    # For debugging
    Write-Information "Combined Roles: $($CombinedRoles -join ', ')"
    return $CombinedRoles
}
