function Set-CIPPDBCacheMailboxes {
    <#
    .SYNOPSIS
        Caches all mailboxes and optionally related data (permissions, rules) for a tenant

    .PARAMETER TenantFilter
        The tenant to cache mailboxes for

    .PARAMETER QueueId
        The queue ID to update with total tasks

    .PARAMETER Types
        Optional array of types to cache. Valid values: 'All', 'Permissions', 'CalendarPermissions', 'Rules'
        If not specified, defaults to 'All' which caches all types.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$TenantFilter,
        [string]$QueueId,
        [ValidateSet('All', 'None', 'Permissions', 'CalendarPermissions', 'Rules')]
        [string[]]$Types = @('All')
    )

    try {
        Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message 'Caching mailboxes' -sev Debug

        # Get mailboxes with select properties
        $Select = 'id,ExchangeGuid,ArchiveGuid,UserPrincipalName,DisplayName,PrimarySMTPAddress,RecipientType,RecipientTypeDetails,EmailAddresses,WhenSoftDeleted,IsInactiveMailbox,ForwardingSmtpAddress,DeliverToMailboxAndForward,ForwardingAddress,HiddenFromAddressListsEnabled,ExternalDirectoryObjectId,MessageCopyForSendOnBehalfEnabled,MessageCopyForSentAsEnabled,GrantSendOnBehalfTo,PersistedCapabilities,LitigationHoldEnabled,LitigationHoldDate,LitigationHoldDuration,ComplianceTagHoldApplied,RetentionHoldEnabled,InPlaceHolds,RetentionPolicy'
        $ExoRequest = @{
            tenantid  = $TenantFilter
            cmdlet    = 'Get-Mailbox'
            cmdParams = @{}
            Select    = $Select
        }
        # Use Generic List for better memory efficiency with large datasets
        $Mailboxes = [System.Collections.Generic.List[PSObject]]::new()
        $RawMailboxes = New-ExoRequest @ExoRequest

        foreach ($Mailbox in $RawMailboxes) {
            $Mailboxes.Add(($Mailbox | Select-Object id, ExchangeGuid, ArchiveGuid, WhenSoftDeleted,
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
                    MessageCopyForSentAsEnabled,
                    LitigationHoldEnabled,
                    LitigationHoldDate,
                    LitigationHoldDuration,
                    @{ Name = 'LicensedForLitigationHold'; Expression = { ($_.PersistedCapabilities -contains 'EXCHANGE_S_ARCHIVE_ADDON' -or $_.PersistedCapabilities -contains 'BPOS_S_ArchiveAddOn' -or $_.PersistedCapabilities -contains 'EXCHANGE_S_ENTERPRISE' -or $_.PersistedCapabilities -contains 'BPOS_S_DlpAddOn' -or $_.PersistedCapabilities -contains 'BPOS_S_Enterprise') } },
                    ComplianceTagHoldApplied,
                    RetentionHoldEnabled,
                    InPlaceHolds,
                    RetentionPolicy,
                    GrantSendOnBehalfTo))
        }

        $Mailboxes | Add-CIPPDbItem -TenantFilter $TenantFilter -Type 'Mailboxes' -AddCount

        Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message "Cached $($Mailboxes.Count) mailboxes successfully" -sev Debug

        # Expand 'All' to all available types
        if ($Types -contains 'All') {
            $Types = @('Permissions', 'CalendarPermissions', 'Rules')
        } elseif ($Types -contains 'None') {
            $Types = @()
        }

        # Process additional types if specified
        if ($Types -and $Types.Count -gt 0) {
            $MailboxCount = ($Mailboxes | Measure-Object).Count
            if ($MailboxCount -gt 0) {
                Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message "Starting batch caching for types: $($Types -join ', ')" -sev Debug
                Write-Information "Starting batch caching for types: $($Types -join ', ')"

                # Batch sizes per type:
                # - Permissions & Rules use New-ExoBulkRequest (single POST), scales well → 50
                # - Calendar makes 2 serial Exchange calls per mailbox, needs smaller batches → 25
                $PermissionBatchSize = 50
                $CalendarBatchSize = 25
                $RulesBatchSize = 50

                # Separate batches for permissions and rules
                $PermissionBatches = [System.Collections.Generic.List[object]]::new()
                $RuleBatches = [System.Collections.Generic.List[object]]::new()
                $AllMailboxData = @($Mailboxes | Select-Object id, UPN, GrantSendOnBehalfTo)
                $AllMailboxUPNs = @($Mailboxes | Select-Object -ExpandProperty UPN)

                # Build permission batches (mailbox + calendar in their respective sizes)
                if ($Types -contains 'Permissions') {
                    $TotalPermBatches = [Math]::Ceiling($Mailboxes.Count / $PermissionBatchSize)
                    for ($i = 0; $i -lt $Mailboxes.Count; $i += $PermissionBatchSize) {
                        $BatchMailboxUPNs = $AllMailboxUPNs[$i..[Math]::Min($i + $PermissionBatchSize - 1, $Mailboxes.Count - 1)]
                        $BatchNumber = [Math]::Floor($i / $PermissionBatchSize) + 1
                        $PermissionBatches.Add([PSCustomObject]@{
                                FunctionName = 'GetMailboxPermissionsBatch'
                                QueueName    = "Mailbox Permissions Batch $BatchNumber/$TotalPermBatches - $TenantFilter"
                                TenantFilter = $TenantFilter
                                Mailboxes    = $BatchMailboxUPNs
                                MailboxData  = $AllMailboxData
                                BatchNumber  = $BatchNumber
                                TotalBatches = $TotalPermBatches
                            })
                    }
                }

                if ($Types -contains 'CalendarPermissions') {
                    $TotalCalBatches = [Math]::Ceiling($Mailboxes.Count / $CalendarBatchSize)
                    for ($i = 0; $i -lt $Mailboxes.Count; $i += $CalendarBatchSize) {
                        $BatchMailboxUPNs = $AllMailboxUPNs[$i..[Math]::Min($i + $CalendarBatchSize - 1, $Mailboxes.Count - 1)]
                        $BatchNumber = [Math]::Floor($i / $CalendarBatchSize) + 1
                        $PermissionBatches.Add([PSCustomObject]@{
                                FunctionName = 'GetCalendarPermissionsBatch'
                                QueueName    = "Calendar Permissions Batch $BatchNumber/$TotalCalBatches - $TenantFilter"
                                TenantFilter = $TenantFilter
                                Mailboxes    = $BatchMailboxUPNs
                                BatchNumber  = $BatchNumber
                                TotalBatches = $TotalCalBatches
                            })
                    }
                }

                # Build rules batches
                if ($Types -contains 'Rules') {
                    $TotalRuleBatches = [Math]::Ceiling($Mailboxes.Count / $RulesBatchSize)
                    for ($i = 0; $i -lt $Mailboxes.Count; $i += $RulesBatchSize) {
                        $BatchMailboxUPNs = $AllMailboxUPNs[$i..[Math]::Min($i + $RulesBatchSize - 1, $Mailboxes.Count - 1)]
                        $BatchNumber = [Math]::Floor($i / $RulesBatchSize) + 1
                        $RuleBatches.Add([PSCustomObject]@{
                                FunctionName = 'GetMailboxRulesBatch'
                                QueueName    = "Mailbox Rules Batch $BatchNumber/$TotalRuleBatches - $TenantFilter"
                                TenantFilter = $TenantFilter
                                Mailboxes    = $BatchMailboxUPNs
                                BatchNumber  = $BatchNumber
                                TotalBatches = $TotalRuleBatches
                            })
                    }
                }

                # Add QueueId to batch items if provided
                if ($QueueId) {
                    foreach ($Batch in $PermissionBatches) {
                        $Batch | Add-Member -NotePropertyName 'QueueId' -NotePropertyValue $QueueId -Force
                    }
                    foreach ($Batch in $RuleBatches) {
                        $Batch | Add-Member -NotePropertyName 'QueueId' -NotePropertyValue $QueueId -Force
                    }
                }

                # Update queue with total additional tasks if QueueId is provided
                $TotalBatchCount = $PermissionBatches.Count + $RuleBatches.Count
                if ($QueueId -and $TotalBatchCount -gt 0) {
                    Update-CippQueueEntry -RowKey $QueueId -TotalTasks $TotalBatchCount -IncrementTotalTasks
                    Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message "Updated queue $QueueId with $TotalBatchCount additional tasks" -sev Debug
                    Write-Information "Updated queue $QueueId with $TotalBatchCount additional tasks"
                }

                # Start separate orchestrator for permissions if we have permission batches
                if ($PermissionBatches.Count -gt 0) {
                    $PermissionInputObject = [PSCustomObject]@{
                        Batch            = @($PermissionBatches)
                        OrchestratorName = "MailboxPermissions_$TenantFilter"
                        PostExecution    = @{
                            FunctionName = 'StoreMailboxPermissions'
                            Parameters   = @{
                                TenantFilter = $TenantFilter
                            }
                        }
                    }
                    Write-Information "Starting permissions caching orchestrator with $($PermissionBatches.Count) batches"
                    Start-CIPPOrchestrator -InputObject $PermissionInputObject
                    Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message "Started permission caching orchestrator with $($PermissionBatches.Count) batches" -sev Debug
                }

                # Start separate orchestrator for rules if we have rule batches
                if ($RuleBatches.Count -gt 0) {
                    $RuleInputObject = [PSCustomObject]@{
                        Batch            = @($RuleBatches)
                        OrchestratorName = "MailboxRules_$TenantFilter"
                        PostExecution    = @{
                            FunctionName = 'StoreMailboxRules'
                            Parameters   = @{
                                TenantFilter = $TenantFilter
                            }
                        }
                    }
                    Write-Information "Starting rules caching orchestrator with $($RuleBatches.Count) batches"
                    Start-CIPPOrchestrator -InputObject $RuleInputObject
                    Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message "Started rules caching orchestrator with $($RuleBatches.Count) batches" -sev Debug
                }

            } else {
                Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message 'No mailboxes found to cache additional data for' -sev Debug
            }
        }

        # Clear mailbox data to free memory
        $Mailboxes = $null
        [System.GC]::Collect()

    } catch {
        Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message "Failed to cache mailboxes: $($_.Exception.Message)" -sev Error
        Write-Information "Failed to cache mailboxes: $($_.Exception.Message)"
    }
}
