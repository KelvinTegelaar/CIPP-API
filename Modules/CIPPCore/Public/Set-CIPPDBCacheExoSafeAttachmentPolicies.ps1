function Set-CIPPDBCacheExoSafeAttachmentPolicies {
    <#
    .SYNOPSIS
        Caches Exchange Online Safe Attachment policies and rules

    .PARAMETER TenantFilter
        The tenant to cache Safe Attachment data for
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$TenantFilter
    )

    try {
        Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message 'Caching Exchange Safe Attachment policies and rules' -sev Debug

        # Get Safe Attachment policies
        $SafeAttachmentPolicies = New-ExoRequest -tenantid $TenantFilter -cmdlet 'Get-SafeAttachmentPolicy'
        if ($SafeAttachmentPolicies) {
            Add-CIPPDbItem -TenantFilter $TenantFilter -Type 'ExoSafeAttachmentPolicies' -Data $SafeAttachmentPolicies
            Add-CIPPDbItem -TenantFilter $TenantFilter -Type 'ExoSafeAttachmentPolicies' -Data $SafeAttachmentPolicies -Count
            Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message "Cached $($SafeAttachmentPolicies.Count) Safe Attachment policies" -sev Debug
        }
        $SafeAttachmentPolicies = $null

        # Get Safe Attachment rules
        $SafeAttachmentRules = New-ExoRequest -tenantid $TenantFilter -cmdlet 'Get-SafeAttachmentRule'
        if ($SafeAttachmentRules) {
            Add-CIPPDbItem -TenantFilter $TenantFilter -Type 'ExoSafeAttachmentRules' -Data $SafeAttachmentRules
            Add-CIPPDbItem -TenantFilter $TenantFilter -Type 'ExoSafeAttachmentRules' -Data $SafeAttachmentRules -Count
            Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message "Cached $($SafeAttachmentRules.Count) Safe Attachment rules" -sev Debug
        }
        $SafeAttachmentRules = $null

    } catch {
        Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message "Failed to cache Safe Attachment data: $($_.Exception.Message)" -sev Error
    }
}
