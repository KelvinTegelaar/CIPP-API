function Set-CIPPDBCacheMailboxes {
    <#
    .SYNOPSIS
        Caches all mailboxes, CAS mailboxes, and mailbox permissions for a tenant

    .PARAMETER TenantFilter
        The tenant to cache mailboxes for
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$TenantFilter
    )

    try {
        Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message 'Caching mailboxes' -sev Info

        # Get mailboxes with select properties
        $Select = 'id,ExchangeGuid,ArchiveGuid,UserPrincipalName,DisplayName,PrimarySMTPAddress,RecipientType,RecipientTypeDetails,EmailAddresses,WhenSoftDeleted,IsInactiveMailbox,ForwardingSmtpAddress,DeliverToMailboxAndForward,ForwardingAddress,HiddenFromAddressListsEnabled,ExternalDirectoryObjectId,MessageCopyForSendOnBehalfEnabled,MessageCopyForSentAsEnabled'
        $ExoRequest = @{
            tenantid  = $TenantFilter
            cmdlet    = 'Get-Mailbox'
            cmdParams = @{}
            Select    = $Select
        }
        $Mailboxes = (New-ExoRequest @ExoRequest) | Select-Object id, ExchangeGuid, ArchiveGuid, WhenSoftDeleted,
            @{ Name = 'UPN'; Expression = { $_.'UserPrincipalName' } },
            @{ Name = 'displayName'; Expression = { $_.'DisplayName' } },
            @{ Name = 'primarySmtpAddress'; Expression = { $_.'PrimarySMTPAddress' } },
            @{ Name = 'recipientType'; Expression = { $_.'RecipientType' } },
            @{ Name = 'recipientTypeDetails'; Expression = { $_.'RecipientTypeDetails' } },
            @{ Name = 'AdditionalEmailAddresses'; Expression = { ($_.'EmailAddresses' | Where-Object { $_ -clike 'smtp:*' }).Replace('smtp:', '') -join ', ' } },
            @{ Name = 'ForwardingSmtpAddress'; Expression = { $_.'ForwardingSmtpAddress' -replace 'smtp:', '' } },
            @{ Name = 'InternalForwardingAddress'; Expression = { $_.'ForwardingAddress' } },
            DeliverToMailboxAndForward,
            HiddenFromAddressListsEnabled,
            ExternalDirectoryObjectId,
            MessageCopyForSendOnBehalfEnabled,
            MessageCopyForSentAsEnabled

        Add-CIPPDbItem -TenantFilter $TenantFilter -Type 'Mailboxes' -Data $Mailboxes
        Add-CIPPDbItem -TenantFilter $TenantFilter -Type 'Mailboxes' -Data $Mailboxes -Count
        Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message 'Cached mailboxes successfully' -sev Info

        # Get CAS mailboxes
        Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message 'Caching CAS mailboxes' -sev Info
        $CASMailboxes = New-GraphGetRequest -uri "https://outlook.office365.com/adminapi/beta/$($TenantFilter)/CasMailbox" -Tenantid $TenantFilter -scope 'ExchangeOnline' -noPagination $true
        Add-CIPPDbItem -TenantFilter $TenantFilter -Type 'CASMailbox' -Data $CASMailboxes
        Add-CIPPDbItem -TenantFilter $TenantFilter -Type 'CASMailbox' -Data $CASMailboxes -Count
        $CASMailboxes = $null
        Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message 'Cached CAS mailboxes successfully' -sev Info

        # Get mailbox permissions using bulk request
        Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message 'Caching mailbox permissions' -sev Info
        $ExoBulkRequests = foreach ($Mailbox in $Mailboxes) {
            @{
                CmdletInput = @{
                    CmdletName = 'Get-MailboxPermission'
                    Parameters = @{ Identity = $Mailbox.UPN }
                }
            }
        }
        $MailboxPermissions = New-ExoBulkRequest -cmdletArray @($ExoBulkRequests) -tenantid $TenantFilter
        Add-CIPPDbItem -TenantFilter $TenantFilter -Type 'MailboxPermissions' -Data $MailboxPermissions
        Add-CIPPDbItem -TenantFilter $TenantFilter -Type 'MailboxPermissions' -Data $MailboxPermissions -Count
        $MailboxPermissions = $null
        $Mailboxes = $null
        Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message 'Cached mailbox permissions successfully' -sev Info

    } catch {
        Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message "Failed to cache mailboxes: $($_.Exception.Message)" -sev Error
    }
}
