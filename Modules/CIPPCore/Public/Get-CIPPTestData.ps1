function Get-CIPPTestData {
    <#
    .SYNOPSIS
        Cached wrapper around New-CIPPDbRequest for test functions

    .DESCRIPTION
        Returns cached tenant data during test suite execution. The cache is
        backed by CIPP.TestDataCache (static ConcurrentDictionary in C#) so
        it is shared across all PowerShell runspaces within the worker process.

    .PARAMETER TenantFilter
        The tenant domain or GUID to filter by

    .PARAMETER Type
        The data type to retrieve (e.g., Users, Groups, ConditionalAccessPolicies)
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $false)]
        [string]$TenantFilter,

        [Parameter(Mandatory = $false)]
        [string]$Type
    )

    # Enforce tenant lock when running inside custom script execution
    if ($script:CIPPLockedTenant) {
        $TenantFilter = $script:CIPPLockedTenant
    }

    if ([string]::IsNullOrWhiteSpace($TenantFilter)) {
        throw 'TenantFilter is required.'
    }

    $CacheKey = '{0}|{1}' -f $TenantFilter, $Type

    $CachedValue = $null
    if ([CIPP.TestDataCache]::TryGet($CacheKey, [ref]$CachedValue)) {
        return $CachedValue
    }

    $Data = New-CIPPDbRequest -TenantFilter $TenantFilter -Type $Type

    [CIPP.TestDataCache]::Set($CacheKey, $Data)

    return $Data
}
