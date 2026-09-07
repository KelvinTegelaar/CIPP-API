function Set-CIPPDBCacheExoSafeLinksPolicies {
    <#
    .SYNOPSIS
        Caches Exchange Online Safe Links policies and rules

    .PARAMETER TenantFilter
        The tenant to cache Safe Links data for

    .PARAMETER QueueId
        The queue ID to update with total tasks (optional)
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$TenantFilter,
        [string]$QueueId
    )

    # Safe Links is a Defender for Office 365 feature. On tenants without it Exchange rejects
    # Get-SafeLinksPolicy, which surfaced as an Error log for every unlicensed tenant on every
    # collection. Skip those tenants and leave the cache untouched, so the tests report the
    # collection as not run (Skipped) rather than as a failure.
    try {
        $Capabilities = Get-CIPPTenantCapabilities -TenantFilter $TenantFilter
        $MDOCapabilities = @('ATP_ENTERPRISE', 'ATP_ENTERPRISE_GOV', 'THREAT_INTELLIGENCE', 'THREAT_INTELLIGENCE_GOV')
        $HasMDO = @($MDOCapabilities | Where-Object { $Capabilities.$_ -eq $true }).Count -gt 0
        if (-not $HasMDO) {
            Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message 'Skipping the Safe Links cache: this tenant is not licensed for Defender for Office 365' -sev Info
            return
        }
    } catch {
        Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message "Could not determine Defender for Office 365 licensing, attempting the Safe Links cache anyway: $($_.Exception.Message)" -sev Debug
    }

    try {
        Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message 'Caching Exchange Safe Links policies and rules' -sev Debug

        # Write unconditionally with -ClearOnEmpty so a successful but empty result records an
        # authoritative Count=0 marker. That marker is what lets the CIS tests tell "collected, no
        # policies" (a real Failed) apart from "never collected" (a Skip) instead of both surfacing
        # as "cache not found".
        $SafeLinksPolicies = @(New-ExoRequest -tenantid $TenantFilter -cmdlet 'Get-SafeLinksPolicy')
        Add-CIPPDbItem -TenantFilter $TenantFilter -Type 'ExoSafeLinksPolicies' -Data $SafeLinksPolicies -AddCount -ClearOnEmpty
        Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message "Cached $($SafeLinksPolicies.Count) Safe Links policies" -sev Debug
        $SafeLinksPolicies = $null

        # Get Safe Links rules
        $SafeLinksRules = @(New-ExoRequest -tenantid $TenantFilter -cmdlet 'Get-SafeLinksRule')
        Add-CIPPDbItem -TenantFilter $TenantFilter -Type 'ExoSafeLinksRules' -Data $SafeLinksRules -AddCount -ClearOnEmpty
        Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message "Cached $($SafeLinksRules.Count) Safe Links rules" -sev Debug
        $SafeLinksRules = $null

    } catch {
        # Rethrow so the collection runner records a real failure, instead of the producer silently
        # reporting success with an empty cache (which surfaced to tests as "cache not found").
        Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message "Failed to cache Safe Links data: $($_.Exception.Message)" -sev Error
        throw
    }
}
