function Start-CIPPMailboxDataStage {
    <#
    .SYNOPSIS
        Starts the next stage of a tenant's chained mailbox permission, calendar and rules collection

    .DESCRIPTION
        The three types run one after another, one run per type. Permissions and calendar run one
        task at a time; rules, lighter on EXO, two. Each run's post-execution (Push-StoreMailboxData)
        stores that type before starting the next stage, so only one type's results are ever held
        at once and EXO never sees two types for one tenant.

        Permission batches carry each mailbox's delegate data, which only the Mailboxes collector
        holds, so they are passed in prebuilt and the permissions stage always comes first.
        Calendar and rules batches need only UPNs, read from the Mailboxes cache when not given.

    .FUNCTIONALITY
        Internal
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$TenantFilter,
        [Parameter(Mandatory = $true)]
        [string[]]$Types,
        [string[]]$Mailboxes,
        [object[]]$PermissionBatches,
        [string]$QueueId
    )

    $Stages = @(@('Permissions', 'CalendarPermissions', 'Rules').Where({ $_ -in $Types }))
    for ($Index = 0; $Index -lt $Stages.Count; $Index++) {
        $Type = $Stages[$Index]
        $Batches = @(if ($Type -eq 'Permissions') {
            @($PermissionBatches).Where({ $_ })
        } else {
            if (-not $Mailboxes) { $Mailboxes = @(@(New-CIPPDbRequest -TenantFilter $TenantFilter -Type 'Mailboxes' -Fields 'UPN').UPN.Where({ $_ })) }
            $Function, $Label = if ($Type -eq 'Rules') { 'GetMailboxRulesBatch', 'Mailbox Rules' } else { 'GetCalendarPermissionsBatch', 'Calendar Permissions' }
            # 320 mailboxes = 32 EXO batches, enough to keep a task's concurrent batches (32 calendar, 16 rules) busy.
            $Total = [Math]::Ceiling($Mailboxes.Count / 320)
            for ($i = 0; $i -lt $Mailboxes.Count; $i += 320) {
                [PSCustomObject]@{
                    FunctionName = $Function
                    QueueName    = "$Label Batch $($i / 320 + 1)/$Total - $TenantFilter"
                    TenantFilter = $TenantFilter
                    Mailboxes    = $Mailboxes[$i..[Math]::Min($i + 319, $Mailboxes.Count - 1)]
                    BatchNumber  = $i / 320 + 1
                    TotalBatches = $Total
                }
            }
        })
        if ($Batches.Count -eq 0) { continue }

        if ($QueueId) {
            foreach ($Batch in $Batches) { $Batch | Add-Member -NotePropertyName 'QueueId' -NotePropertyValue $QueueId -Force }
        }

        $RunName = @{ Permissions = 'MailboxPermissions'; CalendarPermissions = 'CalendarPermissions'; Rules = 'MailboxRules' }[$Type]
        $Started = Start-CIPPOrchestrator -InputObject ([PSCustomObject]@{
                Batch            = $Batches
                OrchestratorName = "${RunName}_$TenantFilter"
                MaxConcurrency   = $(if ($Type -eq 'Rules') { 2 } else { 1 })
                AllowCollision   = $false
                PostExecution    = @{
                    FunctionName = 'StoreMailboxData'
                    Parameters   = @{
                        TenantFilter = $TenantFilter
                        Type         = $Type
                        Batches      = $Batches.Count
                        Remaining    = @($Stages | Select-Object -Skip ($Index + 1))
                        QueueId      = $QueueId
                    }
                }
            })
        # A run of this type is still going (a manual or baseline refresh): it stores this type itself, so
        # carry on with the next stage rather than ending the chain here.
        if ("$Started" -like '*-Skipped') { continue }
        if ($QueueId) { Update-CippQueueEntry -RowKey $QueueId -TotalTasks $Batches.Count -IncrementTotalTasks }
        Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message "Started $Type caching with $($Batches.Count) batches" -sev Debug
        return
    }
}
