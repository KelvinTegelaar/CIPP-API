function Set-CIPPDBCacheExoApplicationAccessPolicies {
    <#
    .SYNOPSIS
        Caches the Exchange application access policies

    .DESCRIPTION
        Application access policies limit which mailboxes an app reaches with the mailbox permissions it holds in
        Entra. Keeps one row per policy and app: the access right (RestrictAccess or DenyAccess), the group and
        whether the policy is valid. A failed read writes nothing and rethrows.

    .PARAMETER TenantFilter
        The tenant to cache application access policies for

    .PARAMETER QueueId
        The queue ID to update with total tasks (optional)
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$TenantFilter,
        [string]$QueueId
    )

    try {
        Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message 'Caching Exchange application access policies' -sev Debug

        $Rows = @(Get-CIPPExoApplicationAccessPolicy -TenantFilter $TenantFilter)

        if ($Rows.Count -gt 0) {
            Add-CIPPDbItem -TenantFilter $TenantFilter -Type 'ExoApplicationAccessPolicies' -Data $Rows -AddCount
        } else {
            # Read successfully with no policy: record the empty set so the report knows no app is limited.
            Add-CIPPDbItem -TenantFilter $TenantFilter -Type 'ExoApplicationAccessPolicies' -Data @() -AddCount -ClearOnEmpty
        }
        Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message "Cached $($Rows.Count) Exchange application access policy entries" -sev Debug
    } catch {
        Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message "Failed to cache Exchange application access policies: $($_.Exception.Message)" -sev Error
        # Rethrow so Invoke-CIPPDBCacheCollection counts the type as failed rather than leaving an old count row looking current.
        throw
    }
}
