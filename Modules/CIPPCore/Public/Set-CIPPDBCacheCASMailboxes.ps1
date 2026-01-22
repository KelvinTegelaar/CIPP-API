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

        # Use Generic List for better memory efficiency with large datasets
        $CASMailboxList = [System.Collections.Generic.List[PSObject]]::new()
        $CASMailboxesResponse = New-ExoRequest -tenantid $TenantFilter -cmdlet 'Get-CasMailbox'
        foreach ($Mailbox in $CASMailboxesResponse) {
            $CASMailboxList.Add($Mailbox)
        }

        Add-CIPPDbItem -TenantFilter $TenantFilter -Type 'CASMailbox' -Data $CASMailboxList.ToArray()
        Add-CIPPDbItem -TenantFilter $TenantFilter -Type 'CASMailbox' -Data @{ Count = $CASMailboxList.Count } -Count

        $CASMailboxesResponse = $null
        $CASMailboxList.Clear()
        $CASMailboxList = $null
        [System.GC]::Collect()

        Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message 'Cached CAS mailboxes successfully' -sev Debug

    } catch {
        Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message "Failed to cache CAS mailboxes: $($_.Exception.Message)" -sev Error
    }
}
