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

        $ZeroArchiveGuid = '00000000-0000-0000-0000-000000000000'
        $Select = 'id,ExchangeGuid,ArchiveGuid,UserPrincipalName,DisplayName,PrimarySMTPAddress,RecipientType,RecipientTypeDetails,EmailAddresses,WhenSoftDeleted,IsInactiveMailbox,ForwardingSmtpAddress,DeliverToMailboxAndForward,ForwardingAddress,HiddenFromAddressListsEnabled,ExternalDirectoryObjectId,MessageCopyForSendOnBehalfEnabled,MessageCopyForSentAsEnabled,GrantSendOnBehalfTo,PersistedCapabilities,LitigationHoldEnabled,LitigationHoldDate,LitigationHoldDuration,ComplianceTagHoldApplied,RetentionHoldEnabled,InPlaceHolds,RetentionPolicy,RemotePowerShellEnabled,Guid,Identity,AutoExpandingArchiveEnabled,ArchiveQuota,IsExchangeCloudManaged,IsDirSynced,MailboxPlan,MailboxPlanId,RecipientLimits,AccountDisabled,AuditEnabled,AuditOwner,AuditDelegate,AuditAdmin,DefaultAuditSet'

        # Streamed a page at a time: the whole tenant is never held, only small per-mailbox lookups.
        $UserLookup = @{}
        New-ExoRequest -tenantid $TenantFilter -cmdlet 'Get-User' -Select 'ExternalDirectoryObjectId,RemotePowerShellEnabled,Guid,Identity' -StreamPages | ForEach-Object {
            foreach ($User in $_.Value) {
                if ($User.ExternalDirectoryObjectId) { $UserLookup[$User.ExternalDirectoryObjectId] = [Tuple[object, object, object]]::new($User.RemotePowerShellEnabled, $User.Guid, $User.Identity) }
            }
        }

        # Separate OrgConfig call (avoid shared mailbox $Select on Get-OrganizationConfig).
        # On failure, fall back to mailbox-only resolution and log so live/cache skew is diagnosable.
        $OrgAutoExpandingArchiveEnabled = $null
        try {
            $OrgAutoExpandingArchiveEnabled = (New-ExoRequest -tenantid $TenantFilter -cmdlet 'Get-OrganizationConfig' -Select 'AutoExpandingArchiveEnabled' -useSystemMailbox $true).AutoExpandingArchiveEnabled
        } catch {
            Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message "Failed to get OrganizationConfig for Auto Expanding Archive; using mailbox-level values only. Error: $($_.Exception.Message)" -sev Warning
        }

        $UsageByUPN = @{}
        try {
            # Piped rather than foreach'd: a foreach keeps the whole report alive until the function returns
            New-GraphGetRequest -uri "https://graph.microsoft.com/beta/reports/getMailboxUsageDetail(period='D7')?`$format=application%2fjson" -tenantid $TenantFilter | ForEach-Object {
                if ($_.userPrincipalName) {
                    $UsageByUPN[$_.userPrincipalName] = [Tuple[long, long, long]]::new(
                        $(try { [int64]$_.storageUsedInBytes } catch { 0 }),
                        $(try { [int64]$_.prohibitSendReceiveQuotaInBytes } catch { 0 }),
                        $(try { [int64]$_.itemCount } catch { 0 }))
                }
            }
        } catch {
            Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message "Failed to cache mailbox usage details: $($_.Exception.Message)" -sev Warning
        }

        # Opened here, not in the ForEach-Object below, so it captures this scope (see Set-CIPPDBCacheGroups)
        $Writer = { Add-CIPPDbItem -TenantFilter $TenantFilter -Type 'Mailboxes' -AddCount }.GetSteppablePipeline()
        $Writer.Begin($true)
        $AeaByValue = @{}
        $QuotaBytes = @{}
        $Mailboxes = [System.Collections.Generic.List[PSObject]]::new()
        New-ExoRequest -tenantid $TenantFilter -cmdlet 'Get-Mailbox' -Select $Select -StreamPages | ForEach-Object {
            $Page = @(foreach ($Mailbox in $_.Value) {
                    # ExternalDirectoryObjectId can be null for a mailbox that has no linked Entra ID
                    # directory object (the $UserLookup population above already guards against this on
                    # the write side - see the -and check a few lines up). Indexing a hashtable with a
                    # null key throws "Index operation failed; the array index evaluated to null." and
                    # aborts the whole cache run for the tenant, so the read side needs the same guard.
                    $MatchedUser = if ($Mailbox.ExternalDirectoryObjectId) { $UserLookup[$Mailbox.ExternalDirectoryObjectId] } else { $null }
                    $AeaKey = "$($Mailbox.AutoExpandingArchiveEnabled)"
                    if (-not $AeaByValue.ContainsKey($AeaKey)) { $AeaByValue[$AeaKey] = Get-CIPPAutoExpandingArchiveState -MailboxAutoExpandingArchiveEnabled $Mailbox.AutoExpandingArchiveEnabled -OrgAutoExpandingArchiveEnabled $OrgAutoExpandingArchiveEnabled }
                    $AutoExpandingArchiveState = $AeaByValue[$AeaKey]
                    $QuotaKey = [string]$Mailbox.ArchiveQuota
                    if (-not $QuotaBytes.ContainsKey($QuotaKey)) { $QuotaBytes[$QuotaKey] = try { Get-ExoOnlineStringBytes -SizeString $QuotaKey } catch { 0 } }
                    $SmtpAliases = @(foreach ($Address in $Mailbox.EmailAddresses) { if ($Address -clike 'smtp:*') { $Address.Replace('smtp:', '') } })
                    $Capabilities = $Mailbox.PersistedCapabilities
                    [PSCustomObject][ordered]@{
                        Id                                = $Mailbox.Id
                        ExchangeGuid                      = $Mailbox.ExchangeGuid
                        ArchiveGuid                       = $Mailbox.ArchiveGuid
                        WhenSoftDeleted                   = $Mailbox.WhenSoftDeleted
                        UPN                               = $Mailbox.UserPrincipalName
                        displayName                       = $Mailbox.DisplayName
                        primarySmtpAddress                = $Mailbox.PrimarySMTPAddress
                        ArchiveEnabled                    = $Mailbox.ArchiveGuid -and $Mailbox.ArchiveGuid.ToString() -ne $ZeroArchiveGuid
                        ArchiveQuota                      = $QuotaBytes[$QuotaKey]
                        AutoExpandingArchive              = $AutoExpandingArchiveState.AutoExpandingArchive
                        AutoExpandingArchiveScope         = $AutoExpandingArchiveState.AutoExpandingArchiveScope
                        ArchiveSize                       = 0
                        ArchiveItemCount                  = 0
                        storageUsedInBytes                = 0
                        prohibitSendReceiveQuotaInBytes   = 0
                        MailboxItemCount                  = 0
                        recipientType                     = $Mailbox.RecipientType
                        recipientTypeDetails              = $Mailbox.RecipientTypeDetails
                        AdditionalEmailAddresses          = if ($SmtpAliases.Count) { $SmtpAliases -join ', ' } else { $null }
                        ForwardingSmtpAddress             = $Mailbox.ForwardingSmtpAddress -replace 'smtp:', ''
                        InternalForwardingAddress         = $Mailbox.ForwardingAddress
                        DeliverToMailboxAndForward        = $Mailbox.DeliverToMailboxAndForward
                        HiddenFromAddressListsEnabled     = $Mailbox.HiddenFromAddressListsEnabled
                        ExternalDirectoryObjectId         = $Mailbox.ExternalDirectoryObjectId
                        MessageCopyForSendOnBehalfEnabled = $Mailbox.MessageCopyForSendOnBehalfEnabled
                        MessageCopyForSentAsEnabled       = $Mailbox.MessageCopyForSentAsEnabled
                        LitigationHoldEnabled             = $Mailbox.LitigationHoldEnabled
                        LitigationHoldDate                = $Mailbox.LitigationHoldDate
                        LitigationHoldDuration            = $Mailbox.LitigationHoldDuration
                        LicensedForLitigationHold         = ($Capabilities -contains 'EXCHANGE_S_ARCHIVE_ADDON' -or $Capabilities -contains 'BPOS_S_ArchiveAddOn' -or $Capabilities -contains 'EXCHANGE_S_ENTERPRISE' -or $Capabilities -contains 'BPOS_S_DlpAddOn' -or $Capabilities -contains 'BPOS_S_Enterprise')
                        ComplianceTagHoldApplied          = $Mailbox.ComplianceTagHoldApplied
                        RetentionHoldEnabled              = $Mailbox.RetentionHoldEnabled
                        InPlaceHolds                      = $Mailbox.InPlaceHolds
                        RetentionPolicy                   = $Mailbox.RetentionPolicy
                        GrantSendOnBehalfTo               = $Mailbox.GrantSendOnBehalfTo
                        IsExchangeCloudManaged            = $Mailbox.IsExchangeCloudManaged
                        IsDirSynced                       = $Mailbox.IsDirSynced
                        MailboxPlan                       = $Mailbox.MailboxPlan
                        MailboxPlanId                     = $Mailbox.MailboxPlanId
                        PersistedCapabilities             = $Capabilities
                        RecipientLimits                   = $Mailbox.RecipientLimits
                        AccountDisabled                   = $Mailbox.AccountDisabled
                        AuditEnabled                      = $Mailbox.AuditEnabled
                        AuditOwner                        = $Mailbox.AuditOwner
                        AuditDelegate                     = $Mailbox.AuditDelegate
                        AuditAdmin                        = $Mailbox.AuditAdmin
                        DefaultAuditSet                   = $Mailbox.DefaultAuditSet
                        RemotePowerShellEnabled           = $MatchedUser.Item1
                        Guid                              = $MatchedUser.Item2
                        Identity                          = $MatchedUser.Item3
                    }
                })

            foreach ($Row in $Page) {
                if ($Row.UPN -and $UsageByUPN.ContainsKey($Row.UPN)) {
                    $Usage = $UsageByUPN[$Row.UPN]
                    $Row.storageUsedInBytes = $Usage.Item1
                    $Row.prohibitSendReceiveQuotaInBytes = $Usage.Item2
                    $Row.MailboxItemCount = $Usage.Item3
                }
            }

            $ArchiveRows = @($Page | Where-Object { $_.ArchiveEnabled -eq $true -and $_.UPN })
            if ($ArchiveRows.Count -gt 0) {
                $ArchiveRowByRequestId = @{}
                $ArchiveStatsRequests = @(foreach ($Row in $ArchiveRows) {
                        $OperationGuid = [Guid]::NewGuid().ToString()
                        $ArchiveRowByRequestId[$OperationGuid] = $Row
                        @{
                            CmdletInput   = @{
                                CmdletName = 'Get-MailboxStatistics'
                                Parameters = @{
                                    Identity = $Row.UPN
                                    Archive  = $true
                                }
                            }
                            OperationGuid = $OperationGuid
                        }
                    })
                foreach ($ArchiveStat in @(New-ExoBulkRequest -tenantid $TenantFilter -cmdletArray $ArchiveStatsRequests -useSystemMailbox $true -MaxConcurrency 5)) {
                    if ($ArchiveStat.OperationGuid -and $ArchiveRowByRequestId.ContainsKey($ArchiveStat.OperationGuid) -and -not $ArchiveStat.error) {
                        $Row = $ArchiveRowByRequestId[$ArchiveStat.OperationGuid]
                        $Row.ArchiveSize = try { Get-ExoOnlineStringBytes -SizeString $ArchiveStat.TotalItemSize } catch { 0 }
                        $Row.ArchiveItemCount = try { [int64]$ArchiveStat.ItemCount } catch { 0 }
                    }
                }
            }

            foreach ($Row in $Page) {
                $Writer.Process($Row)
                $Mailboxes.Add([PSCustomObject]@{ Id = $Row.Id; UPN = $Row.UPN; GrantSendOnBehalfTo = $Row.GrantSendOnBehalfTo })
            }
        }
        $Writer.End()
        $UserLookup = $null
        $UsageByUPN = $null

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
                # - Permissions & Rules use New-ExoBulkRequest (single POST), scales well → 100
                # - Calendar uses 2 bulk phases (folder stats + permissions), handles 100 per activity
                $PermissionBatchSize = 50
                $CalendarBatchSize = 100
                $RulesBatchSize = 100

                # Separate batches for permissions and rules
                $PermissionBatches = [System.Collections.Generic.List[object]]::new()
                $RuleBatches = [System.Collections.Generic.List[object]]::new()
                $AllMailboxUPNs = @($Mailboxes | Select-Object -ExpandProperty UPN)

                # Every permission batch used to carry a copy of all mailboxes. Start-CIPPOrchestrator
                # serialises the entire batch array into one ConvertTo-Json string, so that payload
                # grew with the square of the mailbox count - a 10k-mailbox tenant produced 200
                # batches x 10k entries in a single string.
                #
                # Push-GetMailboxPermissionsBatch only reads MailboxData two ways: it builds an
                # id -> UPN lookup used to resolve send-on-behalf delegates, and it reads
                # GrantSendOnBehalfTo for mailboxes in its own batch. So a batch needs its own
                # mailboxes plus the mailboxes actually referenced as a delegate - never all of them.
                # Delegates that are absent from the lookup are already skipped there, so the
                # narrower slice resolves exactly the same set of delegates.
                $MailboxSlimByUPN = @{}
                foreach ($Mailbox in $Mailboxes) {
                    if ($Mailbox.UPN) {
                        $MailboxSlimByUPN[[string]$Mailbox.UPN] = $Mailbox
                    }
                }

                $DelegateIds = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
                foreach ($Mailbox in $Mailboxes) {
                    foreach ($Delegate in @($Mailbox.GrantSendOnBehalfTo)) {
                        if ($Delegate) { [void]$DelegateIds.Add([string]$Delegate) }
                    }
                }

                # GrantSendOnBehalfTo is dropped here: these entries exist only to resolve a
                # delegate id to a UPN. The mailbox's own batch carries its full entry.
                $DelegateDirectory = @(foreach ($Mailbox in $Mailboxes) {
                        if ($Mailbox.id -and $Mailbox.UPN -and $DelegateIds.Contains([string]$Mailbox.id)) {
                            [PSCustomObject]@{
                                id                  = $Mailbox.id
                                UPN                 = $Mailbox.UPN
                                GrantSendOnBehalfTo = $null
                            }
                        }
                    })
                $DelegateIds = $null

                # Build permission batches (mailbox + calendar in their respective sizes)
                if ($Types -contains 'Permissions') {
                    $TotalPermBatches = [Math]::Ceiling($Mailboxes.Count / $PermissionBatchSize)
                    for ($i = 0; $i -lt $Mailboxes.Count; $i += $PermissionBatchSize) {
                        $BatchMailboxUPNs = $AllMailboxUPNs[$i..[Math]::Min($i + $PermissionBatchSize - 1, $Mailboxes.Count - 1)]
                        $BatchNumber = [Math]::Floor($i / $PermissionBatchSize) + 1

                        # Batch members keep $Mailboxes order, so the send-on-behalf rows this
                        # batch emits come out in the same order as before. Delegate-only entries
                        # are appended and carry no GrantSendOnBehalfTo, so they add no rows.
                        $BatchUPNSet = [System.Collections.Generic.HashSet[string]]::new(
                            [string[]]@($BatchMailboxUPNs), [System.StringComparer]::OrdinalIgnoreCase)
                        $BatchMailboxData = @(
                            foreach ($UPN in $BatchMailboxUPNs) { $MailboxSlimByUPN[[string]$UPN] }
                            foreach ($Entry in $DelegateDirectory) {
                                if (-not $BatchUPNSet.Contains([string]$Entry.UPN)) { $Entry }
                            }
                        )

                        $PermissionBatches.Add([PSCustomObject]@{
                                FunctionName = 'GetMailboxPermissionsBatch'
                                QueueName    = "Mailbox Permissions Batch $BatchNumber/$TotalPermBatches - $TenantFilter"
                                TenantFilter = $TenantFilter
                                Mailboxes    = $BatchMailboxUPNs
                                MailboxData  = $BatchMailboxData
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
        $MailboxSlimByUPN = $null
        $DelegateDirectory = $null
        $AllMailboxUPNs = $null
        $PermissionBatches = $null
        $RuleBatches = $null
        [System.GC]::Collect()

    } catch {
        Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message "Failed to cache mailboxes: $($_.Exception.Message)" -sev Error
        Write-Information "Failed to cache mailboxes: $($_.Exception.Message)"
    }
}
