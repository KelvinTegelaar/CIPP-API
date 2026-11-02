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

    Write-Debug "SWA Roles: $($SwaRoles -join ', ')"
    Write-Debug "Cached Roles: $($CachedRoles -join ', ')"

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
    Write-Debug "Combined Roles: $($CombinedRoles -join ', ')"

    # Apply role impersonation here so every secondary authorization or visibility check
    # that resolves roles through this function (API client grants, Sherweb, alerts,
    # domain health, ...) sees the impersonated role, consistent with Test-CIPPAccess.
    if (![string]::IsNullOrWhiteSpace($Headers.'x-cipp-impersonate-role') -and $CombinedRoles -contains 'superadmin') {
        $Impersonation = Resolve-CippImpersonation -User ([pscustomobject]@{
                identityProvider = 'swa'
                userId           = $null
                userDetails      = $Username
                userRoles        = @($CombinedRoles)
            }) -Request ([pscustomobject]@{ Headers = $Headers })
        return @($Impersonation.User.userRoles)
    }

    return $CombinedRoles
}
