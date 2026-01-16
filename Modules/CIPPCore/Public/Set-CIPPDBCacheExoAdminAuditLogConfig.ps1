function Set-CIPPDBCacheExoAdminAuditLogConfig {
    <#
    .SYNOPSIS
        Caches Exchange Online Admin Audit Log Configuration

    .PARAMETER TenantFilter
        The tenant to cache admin audit log config for
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$TenantFilter
    )

    try {
        Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message 'Caching Exchange Admin Audit Log configuration' -sev Debug

        $AuditConfig = New-ExoRequest -tenantid $TenantFilter -cmdlet 'Get-AdminAuditLogConfig'

        if ($AuditConfig) {
            # AdminAuditLogConfig returns a single object, wrap in array for consistency
            $AuditConfigArray = @($AuditConfig)
            Add-CIPPDbItem -TenantFilter $TenantFilter -Type 'ExoAdminAuditLogConfig' -Data $AuditConfigArray
            Add-CIPPDbItem -TenantFilter $TenantFilter -Type 'ExoAdminAuditLogConfig' -Data $AuditConfigArray -Count
            Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message 'Cached Exchange Admin Audit Log configuration' -sev Debug
        }
        $AuditConfig = $null

    } catch {
        Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message "Failed to cache Admin Audit Log configuration: $($_.Exception.Message)" -sev Error
    }
}
