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

    if (-not $AllPermissionsRow.Permissions) {
        $AllPermissions = Get-CIPPHttpFunctions -ByRole | Select-Object -ExpandProperty Permission
        $Entity = @{
            PartitionKey = 'HttpFunctions'
            RowKey       = 'HttpFunctions'
            Version      = [string]$Version
            Permissions  = [string]($AllPermissions | ConvertTo-Json -Compress)
        }
        Add-CIPPAzDataTableEntity @AllPermissionCacheTable -Entity $Entity -Force
    } else {
        $AllPermissions = $AllPermissionsRow.Permissions | ConvertFrom-Json
    }

    $script:CippHttpPermissions = @($AllPermissions)
    $script:CippHttpPermissionsVersion = $Version
    return $script:CippHttpPermissions
}
