function Push-AuditLogSearchCreationV2 {
    <#
    .SYNOPSIS
        Per-tenant audit-log search creation activity (V2). Seeds owed regular (35-min) and 12-hour
        reconciliation windows into the AuditLogCoverage ledger, then creates Graph searches for the
        due ones - oldest first, capped per cycle, with manual throttle handling.
    .DESCRIPTION
        1. Seed owed regular windows (Get-CippAuditLogPlannedWindows) and reconciliation windows
           (Get-CippAuditLogReconciliationWindows) as Planned ledger rows.
        2. Take the oldest <= MaxPerCycle (6) due Planned windows (regular + reconciliation combined)
           and create a Graph search for each, with auto-retry DISABLED (New-CippAuditLogSearchV2 ->
           maxRetries 1).
        3. Throttling: the createSearch 429 is a per-tenant cap of ~10 concurrent searches, not a rate
           limit, so on a 429 we stop and defer the current window AND all remaining queued windows to
           the next cycle (no Attempts increment - a cap is not a failure, so it never dead-letters).
           Other transient errors (UnknownError, 5xx, gateway) retry the individual window with backoff
           and dead-letter at MaxAttempts. AuditingDisabled and AccessDenied (token failure - e.g.
           AADSTS7000229 missing service principal) cache the tenant as disabled for 24h and stop.

        Capping at 6/cycle keeps us well under the ~10 concurrent-search ceiling (they complete within
        the cycle and free slots). Oldest-first means gaps/backlog/reconciliation drain before the
        freshest window; in steady state only the one new window is due, so latency is unaffected.
    .FUNCTIONALITY
        Entrypoint
    #>
    [CmdletBinding()]
    param($Item)

    $TenantFilter = $Item.TenantFilter
    $TenantId = $Item.TenantId
    $MaxPerCycle = 6
    $MaxAttempts = 8

    try {
        $Ledger = Get-CippTable -TableName 'AuditLogCoverage'
        $Rows = @(Get-CIPPAzDataTableEntity @Ledger -Filter "PartitionKey eq '$TenantFilter'")
        $Now = (Get-Date).ToUniversalTime()

        # 1) Seed owed regular + reconciliation windows as Planned.
        foreach ($Window in (Get-CippAuditLogPlannedWindows -ExistingRows $Rows -Now $Now)) {
            $Entity = @{
                PartitionKey = [string]$TenantFilter; RowKey = [string]$Window.RowKey; TenantId = [string]$TenantId
                WindowStart = [datetime]$Window.WindowStart; WindowEnd = [datetime]$Window.WindowEnd
                State = 'Planned'; Type = 'Window'; Attempts = 0; RetryCount = 0; ThrottleCount = 0; SearchId = ''; LastError = ''
            }
            Add-CIPPAzDataTableEntity @Ledger -Entity $Entity -Force
            $Rows += [pscustomobject]$Entity
        }
        foreach ($Window in (Get-CippAuditLogReconciliationWindows -ExistingRows $Rows -Now $Now)) {
            $Entity = @{
                PartitionKey = [string]$TenantFilter; RowKey = [string]$Window.RowKey; TenantId = [string]$TenantId
                WindowStart = [datetime]$Window.WindowStart; WindowEnd = [datetime]$Window.WindowEnd
                State = 'Planned'; Type = 'Reconciliation'; Attempts = 0; RetryCount = 0; ThrottleCount = 0; SearchId = ''; LastError = ''
            }
            Add-CIPPAzDataTableEntity @Ledger -Entity $Entity -Force
            $Rows += [pscustomobject]$Entity
        }

        # 2) Build the create batch: the freshest regular window FIRST (so live events alert
        #    fast even during a backlog), then the oldest of whatever remains - regular +
        #    reconciliation - to drain gaps before they age out. Reconciliation windows are
        #    never "current"; they flow through the oldest-first backfill slots unchanged.
        $Due = @($Rows | Where-Object {
                $_.State -eq 'Planned' -and (-not $_.NextAttemptUtc -or ([datetimeoffset]$_.NextAttemptUtc).UtcDateTime -le $Now)
            } | Sort-Object @{ Expression = { ([datetimeoffset]$_.WindowStart).UtcDateTime } })
        if ($Due.Count -eq 0) {
            Write-Information "AuditLogV2: no due windows for $TenantFilter"
            return $true
        }
        # Newest regular (14-digit RowKey) window = the live period; reconciliation (RECON-*) is never current.
        $CurrentWindow = @($Due | Where-Object { [string]$_.RowKey -match '^\d{14}$' } | Select-Object -Last 1)
        if ($CurrentWindow.Count -gt 0) {
            $CurrentKey = [string]$CurrentWindow[0].RowKey
            $Backfill = @($Due | Where-Object { [string]$_.RowKey -ne $CurrentKey } | Select-Object -First ($MaxPerCycle - 1))
            $Batch = @($CurrentWindow[0]) + $Backfill
        } else {
            # Only reconciliation windows are due: oldest-first, capped.
            $Batch = @($Due | Select-Object -First $MaxPerCycle)
        }

        # 3) Create searches (no auto-retry). On 429 or a tenant-level disable, defer current +
        #    remaining to next cycle.
        $Bail = $false
        $BailReason = ''
        foreach ($Row in $Batch) {
            if ($Bail) {
                # Deferred (not attempted): just set NextAttemptUtc, leave Attempts/State as Planned.
                Add-CIPPAzDataTableEntity @Ledger -Entity @{
                    PartitionKey = $TenantFilter; RowKey = $Row.RowKey; State = 'Planned'
                    NextAttemptUtc = (Get-CippAuditLogNextAttempt -Attempts 1)
                    ThrottleCount = ([int]$Row.ThrottleCount + 1); LastError = $BailReason; LastErrorUtc = $Now
                } -OperationType UpsertMerge
                continue
            }

            $Start = ([datetimeoffset]$Row.WindowStart).UtcDateTime
            $End = ([datetimeoffset]$Row.WindowEnd).UtcDateTime
            $Result = New-CippAuditLogSearchV2 -TenantFilter $TenantFilter -StartTime $Start -EndTime $End
            $Attempts = [int]$Row.Attempts + 1

            if ($Result.Outcome -eq 'Created' -and $Result.Id) {
                Add-CIPPAzDataTableEntity @Ledger -Entity @{
                    PartitionKey = $TenantFilter; RowKey = $Row.RowKey; State = 'Created'
                    SearchId = [string]$Result.Id; Attempts = 0; CreatedUtc = $Now
                    SearchStatus = [string]$Result.Status; LastPolledUtc = $Now
                } -OperationType UpsertMerge
                Write-Information "AuditLogV2: created search for $TenantFilter window $($Row.RowKey)"
            } elseif ($Result.Throttled) {
                # 429 = tenant cap full. Defer this window (no Attempts bump - a cap isn't a failure) and bail.
                $Bail = $true
                $BailReason = 'Deferred: tenant search cap (429)'
                Add-CIPPAzDataTableEntity @Ledger -Entity @{
                    PartitionKey = $TenantFilter; RowKey = $Row.RowKey; State = 'Planned'
                    NextAttemptUtc = (Get-CippAuditLogNextAttempt -Attempts 1)
                    ThrottleCount = ([int]$Row.ThrottleCount + 1); LastError = 'Tenant search cap (429)'; LastErrorUtc = $Now
                } -OperationType UpsertMerge
                Write-Information "AuditLogV2: 429 for $TenantFilter - deferring this + remaining windows to next cycle"
            } elseif ($Result.Outcome -eq 'AuditingDisabled' -or $Result.Outcome -eq 'AccessDenied') {
                # AuditingDisabled = unified auditing off; AccessDenied = we can't get a token for the
                # tenant at all (e.g. missing service principal). Either way: disable for 24h and stop.
                $Bail = $true
                $BailReason = 'Deferred: tenant audit log collection disabled'
                $DisableStatus = if ($Result.Outcome -eq 'AccessDenied') { [string]$Result.Status } else { 'AuditingDisabledTenant' }
                $LedgerError = if ($Result.Message) { [string]$Result.Message } else { $DisableStatus }
                try {
                    $AuditDisabledTable = Get-CIPPTable -TableName 'AuditLogDisabledTenants'
                    Add-CIPPAzDataTableEntity @AuditDisabledTable -Entity @{
                        PartitionKey = 'AuditDisabledTenant'; RowKey = [string]$TenantFilter; TenantFilter = [string]$TenantFilter
                        Status = $DisableStatus; ExpiresAtUnix = [int64]([datetimeoffset]::UtcNow.AddHours(24).ToUnixTimeSeconds())
                    } -Force
                } catch {}
                Add-CIPPAzDataTableEntity @Ledger -Entity @{ PartitionKey = $TenantFilter; RowKey = $Row.RowKey; State = 'Skipped'; LastError = $LedgerError; LastErrorUtc = $Now } -OperationType UpsertMerge
                Write-Information "AuditLogV2: $DisableStatus for $TenantFilter; disabled for 24h"
            } else {
                # Other transient: retry this window next cycle; dead-letter at cap.
                $RetryTotal = [int]$Row.RetryCount + 1
                if ($Attempts -ge $MaxAttempts) {
                    Add-CIPPAzDataTableEntity @Ledger -Entity @{ PartitionKey = $TenantFilter; RowKey = $Row.RowKey; State = 'DeadLetter'; Attempts = $Attempts; RetryCount = $RetryTotal; LastError = [string]$Result.Message; LastErrorUtc = $Now } -OperationType UpsertMerge
                } else {
                    Add-CIPPAzDataTableEntity @Ledger -Entity @{ PartitionKey = $TenantFilter; RowKey = $Row.RowKey; State = 'Planned'; Attempts = $Attempts; RetryCount = $RetryTotal; NextAttemptUtc = (Get-CippAuditLogNextAttempt -Attempts $Attempts); LastError = [string]$Result.Message; LastErrorUtc = $Now } -OperationType UpsertMerge
                }
            }
        }
        return $true
    } catch {
        Write-Information ('Push-AuditLogSearchCreationV2 error for {0}: {1}' -f $TenantFilter, $_.Exception.Message)
        Write-Information $_.InvocationInfo.PositionMessage
        return $false
    }
}
