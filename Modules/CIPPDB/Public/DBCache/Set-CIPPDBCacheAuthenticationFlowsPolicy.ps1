function Set-CIPPDBCacheAuthenticationFlowsPolicy {
    <#
    .SYNOPSIS
        Caches authentication flows policy for a tenant

    .PARAMETER TenantFilter
        The tenant to cache authentication flows policy for

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
        Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message 'Caching authentication flows policy' -sev Debug

        $AuthFlowPolicy = New-GraphGetRequest -uri 'https://graph.microsoft.com/beta/policies/authenticationFlowsPolicy' -tenantid $TenantFilter -AsApp $true

        if ($AuthFlowPolicy) {
            Add-CIPPDbItem -TenantFilter $TenantFilter -Type 'AuthenticationFlowsPolicy' -Data @($AuthFlowPolicy) -AddCount
            Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message 'Cached authentication flows policy successfully' -sev Debug
        } else {
            # The request succeeded with nothing returned: write the authoritative empty set so the
            # Count marker records a completed collection and stale rows are cleared.
            Add-CIPPDbItem -TenantFilter $TenantFilter -Type 'AuthenticationFlowsPolicy' -Data @() -AddCount -ClearOnEmpty
            Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message 'Cached 0 authentication flows policies (none found)' -sev Debug
        }

    } catch {
        Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message "Failed to cache authentication flows policy: $($_.Exception.Message)" -sev Warning -LogData (Get-CippException -Exception $_)
    }
}
