function Get-CippHttpPermissions {
    <#
    .SYNOPSIS
        Returns the set of API permissions that exist on the current HTTP functions.

    .DESCRIPTION
        Resolves the full permission universe for the running CIPP version from the
        cachehttppermissions table, computing and caching it via Get-CIPPHttpFunctions
        on a cache miss. Results are memoized in-process per version so hot paths
        (Test-CIPPAccess, Get-CippAllowedPermissions) avoid repeated table reads.

    .OUTPUTS
        [string[]] of valid permission names, e.g. 'Exchange.Mailbox.ReadWrite'.

    .FUNCTIONALITY
        Internal
    #>
    [CmdletBinding()]
    param()

    $Version = if ($env:CIPPNG -eq 'true') {
        $env:APP_VERSION
    } else {
        (Get-Content -Path (Join-Path $env:CIPPRootPath 'version_latest.txt')).Trim()
    }

    if ($script:CippHttpPermissions -and $script:CippHttpPermissionsVersion -eq $Version) {
        return $script:CippHttpPermissions
    }

    $AllPermissionCacheTable = Get-CIPPTable -tablename 'cachehttppermissions'
    $AllPermissionsRow = Get-CIPPAzDataTableEntity @AllPermissionCacheTable -Filter "PartitionKey eq 'HttpFunctions' and RowKey eq 'HttpFunctions' and Version eq '$($Version)'"

    # A universe written by an out-of-memory worker is short or garbage and was never recomputed; validate on read and write.
    $Cached = if ($AllPermissionsRow.Permissions) {
        try { @($AllPermissionsRow.Permissions | ConvertFrom-Json -ErrorAction Stop) } catch { @() }
    } else { @() }

    if (Test-CippHttpPermissionUniverse -Permissions $Cached) {
        $AllPermissions = $Cached
    } else {
        if ($AllPermissionsRow.Permissions) {
            Write-Warning "The cached HTTP permission universe for version $Version is not usable ($($Cached.Count) entries); recomputing it."
        }
        $AllPermissions = @(Get-CIPPHttpFunctions -ByRole | Select-Object -ExpandProperty Permission)
        if (Test-CippHttpPermissionUniverse -Permissions $AllPermissions) {
            $Entity = @{
                PartitionKey = 'HttpFunctions'
                RowKey       = 'HttpFunctions'
                Version      = [string]$Version
                Permissions  = [string]($AllPermissions | ConvertTo-Json -Compress)
            }
            Add-CIPPAzDataTableEntity @AllPermissionCacheTable -Entity $Entity -Force
        } else {
            # Serve it uncached so the next request retries.
            Write-Warning "HTTP permission enumeration returned $($AllPermissions.Count) entries, which is not a complete universe; not caching it."
            return @($AllPermissions)
        }
    }

    $script:CippHttpPermissions = @($AllPermissions)
    $script:CippHttpPermissionsVersion = $Version
    return $script:CippHttpPermissions
}

