function Set-CIPPDBCacheCASMailboxes {
    <#
    .SYNOPSIS
        Caches all CAS mailboxes for a tenant

    .PARAMETER TenantFilter
        The tenant to cache CAS mailboxes for

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
        Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message 'Caching CAS mailboxes' -sev Debug

        # Stream CAS mailboxes directly to batch processor
        $SmtpAuthOverrides = [System.Collections.Generic.List[object]]::new()
        New-ExoRequest -tenantid $TenantFilter -cmdlet 'Get-CasMailbox' -StreamPages | ForEach-Object { $_.Value } | ForEach-Object {
            if ($_ -and $_.SmtpClientAuthenticationDisabled -eq $false) { $SmtpAuthOverrides.Add($_) }
            $_
        } | Add-CIPPDbItem -TenantFilter $TenantFilter -Type 'CASMailbox' -AddCount
        Add-CIPPDbItem -TenantFilter $TenantFilter -Type 'ExoCASMailboxSmtpAuth' -Data @($SmtpAuthOverrides) -AddCount -ClearOnEmpty

        Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message 'Cached CAS mailboxes successfully' -sev Debug

    } catch {
        Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message "Failed to cache CAS mailboxes: $($_.Exception.Message)" -sev Error
    }
}
