function Set-CIPPDBCacheExoSafeAttachmentPolicies {
    <#
    .SYNOPSIS
        Caches Exchange Online Safe Attachment policies and rules

    .PARAMETER TenantFilter
        The tenant to cache Safe Attachment data for

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
        Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message 'Caching Exchange Safe Attachment policies and rules' -sev Debug

        # Write unconditionally with -ClearOnEmpty so a successful but empty result records an
        # authoritative Count=0 marker. That marker is what lets the CIS tests tell "collected, no
        # policies" (a real Failed) apart from "never collected" (a Skip) instead of both surfacing
        # as "cache not found".
        $SafeAttachmentPolicies = @(New-ExoRequest -tenantid $TenantFilter -cmdlet 'Get-SafeAttachmentPolicy')
        Add-CIPPDbItem -TenantFilter $TenantFilter -Type 'ExoSafeAttachmentPolicies' -Data $SafeAttachmentPolicies -AddCount -ClearOnEmpty
        Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message "Cached $($SafeAttachmentPolicies.Count) Safe Attachment policies" -sev Debug
        $SafeAttachmentPolicies = $null

        # Get Safe Attachment rules
        $SafeAttachmentRules = @(New-ExoRequest -tenantid $TenantFilter -cmdlet 'Get-SafeAttachmentRule')
        Add-CIPPDbItem -TenantFilter $TenantFilter -Type 'ExoSafeAttachmentRules' -Data $SafeAttachmentRules -AddCount -ClearOnEmpty
        Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message "Cached $($SafeAttachmentRules.Count) Safe Attachment rules" -sev Debug
        $SafeAttachmentRules = $null

    } catch {
        # Rethrow so the collection runner records a real failure, instead of the producer silently
        # reporting success with an empty cache (which surfaced to tests as "cache not found").
        Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message "Failed to cache Safe Attachment data: $($_.Exception.Message)" -sev Error
        throw
    }
}
