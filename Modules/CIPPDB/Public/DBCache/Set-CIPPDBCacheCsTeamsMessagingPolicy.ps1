function Set-CIPPDBCacheCsTeamsMessagingPolicy {
    <#
    .SYNOPSIS
        Caches the Teams Messaging Policy (Global)

    .DESCRIPTION
        Calls Get-CsTeamsMessagingPolicy via New-TeamsRequestV2 and writes the
        result into the CippReportingDB under Type 'CsTeamsMessagingPolicy'.
        Used by CIS tests 8.2.3 (external Teams users initiating chat) and
        8.6.1 (security reporting in Teams).

    .PARAMETER TenantFilter
        The tenant to cache the messaging policy for

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
        Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message 'Caching Teams Messaging Policy' -sev Debug

        $MessagingPolicy = New-TeamsRequestV2 -TenantFilter $TenantFilter -Type 'TeamsMessagingPolicy' -Action Get -Identity 'Global'

        if ($MessagingPolicy) {
            $Data = @($MessagingPolicy)
            Add-CIPPDbItem -TenantFilter $TenantFilter -Type 'CsTeamsMessagingPolicy' -Data $Data -AddCount
            Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message 'Cached Teams Messaging Policy' -sev Debug
        } else {
            # The request succeeded with nothing returned: write the authoritative empty set so the
            # Count marker records a completed collection and stale rows are cleared.
            Add-CIPPDbItem -TenantFilter $TenantFilter -Type 'CsTeamsMessagingPolicy' -Data @() -AddCount -ClearOnEmpty
            Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message 'Cached 0 Teams Messaging Policies (none found)' -sev Debug
        }
        $MessagingPolicy = $null

    } catch {
        Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message "Failed to cache Teams Messaging Policy: $($_.Exception.Message)" -sev Error
    }
}
