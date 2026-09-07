function Set-CIPPDBCacheB2BManagementPolicy {
    <#
    .SYNOPSIS
        Caches B2B management policy for a tenant

    .PARAMETER TenantFilter
        The tenant to cache B2B management policy for

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
        Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message 'Caching B2B management policy' -sev Debug

        $LegacyPolicies = New-GraphGetRequest -uri 'https://graph.microsoft.com/beta/policies/b2bManagementPolicies' -tenantid $TenantFilter

        # Keep the raw rows, but project the settings buried in the definition JSON blob so consumers
        # (e.g. the CollaborationDomainRestriction compare) do not have to re-parse it. The actual
        # settings live in definition[0] as a JSON string:
        # {"B2BManagementPolicy":{"InvitationsAllowedAndBlockedDomainsPolicy":{"AllowedDomains":[],"BlockedDomains":[]},...}}
        $B2BManagementPolicy = foreach ($Policy in @($LegacyPolicies)) {
            if ($null -eq $Policy) { continue }
            $ParsedDefinition = $null
            if ($Policy.definition) {
                try { $ParsedDefinition = @($Policy.definition)[0] | ConvertFrom-Json } catch { $ParsedDefinition = $null }
            }
            $DomainPolicy = $ParsedDefinition.B2BManagementPolicy.InvitationsAllowedAndBlockedDomainsPolicy
            $AllowedDomains = @($DomainPolicy.AllowedDomains)
            $BlockedDomains = @($DomainPolicy.BlockedDomains)
            $Policy | Add-Member -NotePropertyMembers ([ordered]@{
                    parsedDefinition = $ParsedDefinition
                    allowedDomains   = $AllowedDomains
                    blockedDomains   = $BlockedDomains
                    hasRestrictions  = (($AllowedDomains.Count -gt 0) -or ($BlockedDomains.Count -gt 0))
                }) -Force
            $Policy
        }

        if ($B2BManagementPolicy) {
            Add-CIPPDbItem -TenantFilter $TenantFilter -Type 'B2BManagementPolicy' -Data @($B2BManagementPolicy) -AddCount
            Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message 'Cached B2B management policy successfully' -sev Debug
        } else {
            # The read succeeded and the tenant genuinely has no legacy B2B policy: write the
            # authoritative empty set so the Count marker records a completed collection and
            # stale rows are cleared, instead of leaving the type indistinguishable from
            # "collector never ran".
            Add-CIPPDbItem -TenantFilter $TenantFilter -Type 'B2BManagementPolicy' -Data @() -AddCount -ClearOnEmpty
            Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message 'No B2B management policy found - cached authoritative empty set' -sev Debug
        }

    } catch {
        Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message "Failed to cache B2B management policy: $($_.Exception.Message)" -sev Warning -LogData (Get-CippException -Exception $_)
    }
}
