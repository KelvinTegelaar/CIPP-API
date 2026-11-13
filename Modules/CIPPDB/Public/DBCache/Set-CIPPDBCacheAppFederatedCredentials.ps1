function Set-CIPPDBCacheAppFederatedCredentials {
    <#
    .SYNOPSIS
        Caches the federated identity credentials of the tenant's app registrations

    .DESCRIPTION
        A federated credential lets tokens from another identity provider sign in as the app without a secret or
        certificate. Keeps one row per credential: the app registration, issuer, subject, audiences and any claims
        matching expression. A failed read writes nothing and rethrows.

    .PARAMETER TenantFilter
        The tenant to cache federated credentials for

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
        Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message 'Caching app federated credentials' -sev Debug

        $Rows = @(Get-CIPPAppFederatedCredential -TenantFilter $TenantFilter)

        if ($Rows.Count -gt 0) {
            Add-CIPPDbItem -TenantFilter $TenantFilter -Type 'AppFederatedCredentials' -Data $Rows -AddCount
        } else {
            # Read successfully with no credential: record the empty set so the report knows the apps were checked.
            Add-CIPPDbItem -TenantFilter $TenantFilter -Type 'AppFederatedCredentials' -Data @() -AddCount -ClearOnEmpty
        }
        Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message "Cached $($Rows.Count) app federated credentials" -sev Debug
    } catch {
        Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message "Failed to cache app federated credentials: $($_.Exception.Message)" -sev Error
        # Rethrow so Invoke-CIPPDBCacheCollection counts the type as failed rather than leaving an old count row looking current.
        throw
    }
}
