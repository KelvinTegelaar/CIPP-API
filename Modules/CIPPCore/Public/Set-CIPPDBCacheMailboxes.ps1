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
        [ValidateSet('All', 'Permissions', 'CalendarPermissions', 'Rules')]
        [string[]]$Types = @('All')
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
                    MessageCopyForSentAsEnabled))
        }

        $Mailboxes | Add-CIPPDbItem -TenantFilter $TenantFilter -Type 'Mailboxes' -AddCount

        Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message "Cached $($Mailboxes.Count) mailboxes successfully" -sev Debug

        # Expand 'All' to all available types
        if ($Types -contains 'All') {
            $Types = @('Permissions', 'CalendarPermissions', 'Rules')
        }

        # Process additional types if specified
        if ($Types -and $Types.Count -gt 0) {
            $MailboxCount = ($Mailboxes | Measure-Object).Count
            if ($MailboxCount -gt 0) {
                Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message "Starting batch caching for types: $($Types -join ', ')" -sev Debug
                Write-Information "Starting batch caching for types: $($Types -join ', ')"

                # Create batches based on selected types
                $BatchSize = 10
                $TotalBatches = [Math]::Ceiling($Mailboxes.Count / $BatchSize)

                # Separate batches for permissions and rules
                $PermissionBatches = [System.Collections.Generic.List[object]]::new()
                $RuleBatches = [System.Collections.Generic.List[object]]::new()

                for ($i = 0; $i -lt $Mailboxes.Count; $i += $BatchSize) {
                    $BatchMailboxes = $Mailboxes[$i..[Math]::Min($i + $BatchSize - 1, $Mailboxes.Count - 1)]
                    $BatchMailboxUPNs = $BatchMailboxes | Select-Object -ExpandProperty UPN
                    $BatchNumber = [Math]::Floor($i / $BatchSize) + 1

                    # Add mailbox permissions batch if requested
                    if ($Types -contains 'Permissions') {
                        $PermissionBatches.Add([PSCustomObject]@{
                                FunctionName = 'GetMailboxPermissionsBatch'
                                QueueName    = "Mailbox Permissions Batch $BatchNumber/$TotalBatches - $TenantFilter"
                                TenantFilter = $TenantFilter
                                Mailboxes    = $BatchMailboxUPNs
                                BatchNumber  = $BatchNumber
                                TotalBatches = $TotalBatches
                            })
                    }

                    # Add calendar permissions batch if requested
                    if ($Types -contains 'CalendarPermissions') {
                        $PermissionBatches.Add([PSCustomObject]@{
                                FunctionName = 'GetCalendarPermissionsBatch'
                                QueueName    = "Calendar Permissions Batch $BatchNumber/$TotalBatches - $TenantFilter"
                                TenantFilter = $TenantFilter
                                Mailboxes    = $BatchMailboxUPNs
                                BatchNumber  = $BatchNumber
                                TotalBatches = $TotalBatches
                            })
                    }

                    # Add mailbox rules batch if requested
                    if ($Types -contains 'Rules') {
                        $RuleBatches.Add([PSCustomObject]@{
                                FunctionName = 'GetMailboxRulesBatch'
                                QueueName    = "Mailbox Rules Batch $BatchNumber/$TotalBatches - $TenantFilter"
                                TenantFilter = $TenantFilter
                                Mailboxes    = $BatchMailboxUPNs
                                BatchNumber  = $BatchNumber
                                TotalBatches = $TotalBatches
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
                    Start-NewOrchestration -FunctionName 'CIPPOrchestrator' -InputObject ($PermissionInputObject | ConvertTo-Json -Compress -Depth 5)
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
                    Start-NewOrchestration -FunctionName 'CIPPOrchestrator' -InputObject ($RuleInputObject | ConvertTo-Json -Compress -Depth 5)
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
