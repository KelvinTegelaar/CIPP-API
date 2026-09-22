function Set-CIPPDBCacheAuthenticationMethodsPolicy {
    <#
    .SYNOPSIS
        Caches authentication methods policy for a tenant

    .PARAMETER TenantFilter
        The tenant to cache authentication methods policy for

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
        Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message 'Caching authentication methods policy' -sev Debug
        $AuthMethodsPolicy = New-GraphGetRequest -uri 'https://graph.microsoft.com/beta/policies/authenticationMethodsPolicy' -tenantid $TenantFilter
        Add-CIPPDbItem -TenantFilter $TenantFilter -Type 'AuthenticationMethodsPolicy' -Data @($AuthMethodsPolicy) -AddCount
        $AuthMethodsPolicy = $null

        Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message 'Cached authentication methods policy successfully' -sev Debug

        # The fido2 entry embedded in the policy above carries defaultPasskeyProfile (structural
        # property) but NOT passkeyProfiles: in the Graph beta metadata passkeyProfiles is a
        # navigation property, so it is only serialized on a direct GET of the fido2 configuration.
        # FIDO2PasskeyProfiles needs both, so fetch and cache the fido2 configuration directly,
        # app-only to match how that standard reads it.
        try {
            $Fido2Configuration = New-GraphGetRequest -uri 'https://graph.microsoft.com/beta/policies/authenticationMethodsPolicy/authenticationMethodConfigurations/fido2' -tenantid $TenantFilter -AsApp $true
            if ($Fido2Configuration) {
                Add-CIPPDbItem -TenantFilter $TenantFilter -Type 'Fido2Configuration' -Data @($Fido2Configuration) -AddCount
                Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message 'Cached FIDO2 authentication method configuration successfully' -sev Debug
            } else {
                # The request succeeded with nothing returned: write the authoritative empty set so the
                # Count marker records a completed collection and stale rows are cleared.
                Add-CIPPDbItem -TenantFilter $TenantFilter -Type 'Fido2Configuration' -Data @() -AddCount -ClearOnEmpty
                Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message 'Cached 0 FIDO2 authentication method configurations (none found)' -sev Debug
            }
            $Fido2Configuration = $null
        } catch {
            Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message "Failed to cache FIDO2 authentication method configuration: $($_.Exception.Message)" -sev Warning
        }

    } catch {
        Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message "Failed to cache authentication methods policy: $($_.Exception.Message)" -sev Error
    }
}
