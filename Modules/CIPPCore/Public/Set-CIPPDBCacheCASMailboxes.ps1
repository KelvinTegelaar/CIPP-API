function Set-CIPPDBCacheCASMailboxes {
    <#
    .SYNOPSIS
        Caches all CAS mailboxes for a tenant

    .PARAMETER TenantFilter
        The tenant to cache CAS mailboxes for
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$TenantFilter
    )

    try {
        Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message 'Caching CAS mailboxes' -sev Debug

        # Stream CAS mailboxes directly to batch processor
        New-ExoRequest -tenantid $TenantFilter -cmdlet 'Get-CasMailbox' |
            Add-CIPPDbItem -TenantFilter $TenantFilter -Type 'CASMailbox' -AddCount

        Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message 'Cached CAS mailboxes successfully' -sev Debug

    } catch {
        Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message "Failed to cache CAS mailboxes: $($_.Exception.Message)" -sev Error
    }
}
