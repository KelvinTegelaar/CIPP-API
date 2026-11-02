function Set-CIPPDBCacheExoAtpPolicyForO365 {
    <#
    .SYNOPSIS
        Caches Exchange Online ATP policies for Office 365

    .PARAMETER TenantFilter
        The tenant to cache ATP policy data for

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
        Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message 'Caching Exchange ATP policies for Office 365' -sev Debug

        # Write unconditionally with -ClearOnEmpty so a successful but empty result records an
        # authoritative Count=0 marker. That marker is what lets the CIS test tell "collected, no
        # policy" (a real Failed) apart from "never collected" (a Skip) instead of both surfacing
        # as "cache not found".
        $AtpPolicies = @(New-ExoRequest -tenantid $TenantFilter -cmdlet 'Get-AtpPolicyForO365')
        Add-CIPPDbItem -TenantFilter $TenantFilter -Type 'ExoAtpPolicyForO365' -Data $AtpPolicies -AddCount -ClearOnEmpty
        Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message "Cached $($AtpPolicies.Count) ATP policies for Office 365" -sev Debug
        $AtpPolicies = $null

    } catch {
        # Rethrow so the collection runner records a real failure, instead of the producer silently
        # reporting success with an empty cache (which surfaced to tests as "cache not found").
        Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message "Failed to cache ATP policy data: $($_.Exception.Message)" -sev Error
        throw
    }
}
