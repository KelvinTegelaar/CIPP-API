function Set-CIPPDBCacheExoSafeAttachmentPolicy {
    <#
    .SYNOPSIS
        Caches Exchange Online Safe Attachment policies (detailed)

    .PARAMETER TenantFilter
        The tenant to cache Safe Attachment policy data for
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$TenantFilter
    )

    try {
        Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message 'Caching Exchange Safe Attachment policies (detailed)' -sev Debug

        $SafeAttachmentPolicies = New-ExoRequest -tenantid $TenantFilter -cmdlet 'Get-SafeAttachmentPolicy'
        if ($SafeAttachmentPolicies) {
            Add-CIPPDbItem -TenantFilter $TenantFilter -Type 'ExoSafeAttachmentPolicy' -Data $SafeAttachmentPolicies
            Add-CIPPDbItem -TenantFilter $TenantFilter -Type 'ExoSafeAttachmentPolicy' -Data $SafeAttachmentPolicies -Count
            Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message "Cached $($SafeAttachmentPolicies.Count) Safe Attachment policies (detailed)" -sev Debug
        }
        $SafeAttachmentPolicies = $null

    } catch {
        Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message "Failed to cache Safe Attachment policy data: $($_.Exception.Message)" -sev Error
    }
}
