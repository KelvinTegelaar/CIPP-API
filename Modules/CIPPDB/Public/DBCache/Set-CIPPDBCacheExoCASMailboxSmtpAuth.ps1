function Set-CIPPDBCacheExoCASMailboxSmtpAuth {
    <#
    .SYNOPSIS
        Caches CAS mailboxes with an explicit SMTP AUTH enablement override for a tenant

    .DESCRIPTION
        SmtpClientAuthenticationDisabled on a CAS mailbox is $null (inherit the tenant
        default), $true (explicitly disabled) or $false (explicitly ENABLED - the override
        that keeps SMTP basic auth alive even after the tenant-wide switch is off). Only
        the explicitly-enabled overrides are cached: that set is what the
        DisableBasicAuthSMTP baseline grades and clears, and it is small.

    .PARAMETER TenantFilter
        The tenant to cache SMTP AUTH overrides for

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
        Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message 'Caching CAS mailbox SMTP AUTH overrides' -sev Debug
        $Overrides = New-ExoRequest -tenantid $TenantFilter -cmdlet 'Get-CASMailbox' -cmdParams @{ Filter = 'SmtpClientAuthenticationDisabled -eq $false'; Properties = @('SmtpClientAuthenticationDisabled') }
        Add-CIPPDbItem -TenantFilter $TenantFilter -Type 'ExoCASMailboxSmtpAuth' -Data @($Overrides | Where-Object { $_ }) -AddCount -ClearOnEmpty
        $Overrides = $null

        Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message 'Cached CAS mailbox SMTP AUTH overrides successfully' -sev Debug

    } catch {
        Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message "Failed to cache CAS mailbox SMTP AUTH overrides: $($_.Exception.Message)" -sev Error
    }
}
