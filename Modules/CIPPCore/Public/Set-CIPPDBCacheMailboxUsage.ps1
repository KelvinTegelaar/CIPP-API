function Set-CIPPDBCacheMailboxUsage {
    <#
    .SYNOPSIS
        Caches mailbox usage details for a tenant

    .PARAMETER TenantFilter
        The tenant to cache mailbox usage for

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
        Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message 'Caching mailbox usage' -sev Debug

        $MailboxUsage = New-GraphGetRequest -uri "https://graph.microsoft.com/beta/reports/getMailboxUsageDetail(period='D7')?`$format=application%2fjson" -tenantid $TenantFilter
        Add-CIPPDbItem -TenantFilter $TenantFilter -Type 'MailboxUsage' -Data $MailboxUsage
        Add-CIPPDbItem -TenantFilter $TenantFilter -Type 'MailboxUsage' -Data $MailboxUsage -Count
        $MailboxUsage = $null
        Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message 'Cached mailbox usage successfully' -sev Debug

    } catch {
        Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message "Failed to cache mailbox usage: $($_.Exception.Message)" -sev Error
    }
}
