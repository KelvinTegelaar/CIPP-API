function Set-CIPPDBCacheOwaMailboxPolicy {
    <#
    .SYNOPSIS
        Caches Exchange Online OWA Mailbox Policies

    .DESCRIPTION
        Calls Get-OwaMailboxPolicy via New-ExoRequest and writes the result
        into the CippReportingDB under Type 'OwaMailboxPolicy'. Used by CIS
        test 6.5.3 (additional storage providers in OWA) and the manual form
        of 1.3.9 (BookingsMailboxCreationEnabled).

    .PARAMETER TenantFilter
        The tenant to cache OWA mailbox policies for

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
        Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message 'Caching OWA Mailbox Policies' -sev Debug

        $OwaMailboxPolicies = New-ExoRequest -tenantid $TenantFilter -cmdlet 'Get-OwaMailboxPolicy'

        if ($OwaMailboxPolicies) {
            Add-CIPPDbItem -TenantFilter $TenantFilter -Type 'OwaMailboxPolicy' -Data $OwaMailboxPolicies
            Add-CIPPDbItem -TenantFilter $TenantFilter -Type 'OwaMailboxPolicy' -Data $OwaMailboxPolicies -Count
            Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message "Cached $($OwaMailboxPolicies.Count) OWA Mailbox Policies" -sev Debug
        }
        $OwaMailboxPolicies = $null

    } catch {
        Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message "Failed to cache OWA Mailbox Policies: $($_.Exception.Message)" -sev Error
    }
}
