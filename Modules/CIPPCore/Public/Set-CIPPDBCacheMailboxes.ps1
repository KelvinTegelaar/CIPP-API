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
        Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message 'Caching mailboxes' -sev Debug

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
        Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message "Cached $($Mailboxes.Count) mailboxes successfully" -sev Debug

        # Get CAS mailboxes
        Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message 'Caching CAS mailboxes' -sev Debug
        $CASMailboxes = New-GraphGetRequest -uri "https://outlook.office365.com/adminapi/beta/$($TenantFilter)/CasMailbox" -Tenantid $TenantFilter -scope 'ExchangeOnline' -noPagination $true
        Add-CIPPDbItem -TenantFilter $TenantFilter -Type 'CASMailbox' -Data $CASMailboxes
        Add-CIPPDbItem -TenantFilter $TenantFilter -Type 'CASMailbox' -Data $CASMailboxes -Count
        $CASMailboxes = $null
        Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message 'Cached CAS mailboxes successfully' -sev Debug

        # Start orchestrator to cache mailbox permissions in batches
        $MailboxCount = ($Mailboxes | Measure-Object).Count
        if ($MailboxCount -gt 0) {
            Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message "Starting mailbox permission caching for $MailboxCount mailboxes" -sev Debug
            
            # Create batches of 10 mailboxes each
            $BatchSize = 10
            $Batches = [System.Collections.Generic.List[object]]::new()
            
            for ($i = 0; $i -lt $Mailboxes.Count; $i += $BatchSize) {
                $BatchMailboxes = $Mailboxes[$i..[Math]::Min($i + $BatchSize - 1, $Mailboxes.Count - 1)]
                
                # Only send UPN to batch function to reduce payload size
                $BatchMailboxUPNs = $BatchMailboxes | Select-Object -ExpandProperty UPN
                
                $Batches.Add([PSCustomObject]@{
                    FunctionName = 'GetMailboxPermissionsBatch'
                    TenantFilter = $TenantFilter
                    Mailboxes    = $BatchMailboxUPNs
                    BatchNumber  = [Math]::Floor($i / $BatchSize) + 1
                    TotalBatches = [Math]::Ceiling($Mailboxes.Count / $BatchSize)
                })
            }
            
            $InputObject = [PSCustomObject]@{
                Batch            = $Batches
                OrchestratorName = "MailboxPermissions_$TenantFilter"
                DurableMode      = 'Sequence'
                PostExecution    = @{
                    FunctionName = 'StoreMailboxPermissions'
                    Parameters   = @{
                        TenantFilter = $TenantFilter
                    }
                }
            }
            Start-NewOrchestration -FunctionName 'CIPPOrchestrator' -InputObject ($InputObject | ConvertTo-Json -Compress -Depth 5)
            Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message "Started mailbox permission caching orchestrator with $($Batches.Count) batches" -sev Debug
        } else {
            Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message 'No mailboxes found to cache permissions for' -sev Debug
        }

    } catch {
        Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message "Failed to cache mailboxes: $($_.Exception.Message)" -sev Error
    }
}
