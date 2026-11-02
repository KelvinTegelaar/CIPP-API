function Push-AuditLogSearchCreationV2 {
    <#
    .SYNOPSIS
        Audit-log search creation activity (V2) for a chunk of tenants. Seeds owed regular (35-min) and 12-hour
        reconciliation windows into the AuditLogCoverage ledger, then creates the Graph searches for every
        tenant's due windows in one concurrent multi-tenant call.
    .DESCRIPTION
        Per tenant:
        1. Plan owed regular windows (Get-CippAuditLogPlannedWindows) and reconciliation windows
           (Get-CippAuditLogReconciliationWindows).
        2. Take the freshest regular window plus the oldest of the remaining due windows, <= MaxPerCycle (6).
        Then every tenant's searches are created together (New-CippAuditLogSearchV2: one $batch per tenant,
        tenants sent concurrently), and each tenant's ledger rows are written in one call with their outcome:
          * Created -> State Created with the SearchId.
          * 429 -> the tenant's ~10 concurrent-search cap is full: stays Planned for the next cycle, no Attempts
            increment (a cap is not a failure, so it never dead-letters).
          * AuditingDisabled / AccessDenied -> Skipped, and the tenant is disabled for 24h.
          * Other transient errors (already re-sent in-call) -> Planned with backoff, dead-lettered at MaxAttempts.

        Capping at 6/cycle keeps each tenant under the ~10 concurrent-search ceiling. In steady state only the one
        new window is due per tenant.
    .FUNCTIONALITY
        Entrypoint
    #>
    [CmdletBinding()]
    param($Item)

    $MaxPerCycle = 6
    $MaxAttempts = 8
    # Items queued before chunking carry a single tenant.
    $Tenants = if ($Item.Tenants) { @($Item.Tenants) } else { @([pscustomobject]@{ TenantFilter = $Item.TenantFilter; TenantId = $Item.TenantId }) }

    $Ledger = Get-CippTable -TableName 'AuditLogCoverage'
    $Now = (Get-Date).ToUniversalTime()
    $Plans = [System.Collections.Generic.List[object]]::new()
    $Searches = [System.Collections.Generic.List[object]]::new()

    foreach ($Tenant in $Tenants) {
        $TenantFilter = [string]$Tenant.TenantFilter
        try {
            # Whole partition: re-planned MANUAL-* rows need re-creating too. No split markers - these rows never split.
            $TenantKey = $TenantFilter.Replace("'", "''")
            $Rows = [System.Collections.Generic.List[object]]::new()
            foreach ($Row in @(Get-CIPPAzDataTableEntity @Ledger -Filter "PartitionKey eq '$TenantKey'" `
                        -Property 'RowKey', 'WindowStart', 'WindowEnd', 'State', 'NextAttemptUtc', 'Attempts', 'RetryCount', 'ThrottleCount')) {
                $Rows.Add($Row)
            }

            # 1) Owed windows join the plan as Planned rows; they are written below together with their outcome.
            $New = @{}
            foreach ($Window in (Get-CippAuditLogPlannedWindows -ExistingRows $Rows -Now $Now)) {
                $Row = [pscustomobject]@{ RowKey = [string]$Window.RowKey; WindowStart = [datetime]$Window.WindowStart; WindowEnd = [datetime]$Window.WindowEnd; State = 'Planned'; Type = 'Window' }
                $New[$Row.RowKey] = $Row
                $Rows.Add($Row)
            }
            foreach ($Window in (Get-CippAuditLogReconciliationWindows -ExistingRows $Rows -Now $Now)) {
                $Row = [pscustomobject]@{ RowKey = [string]$Window.RowKey; WindowStart = [datetime]$Window.WindowStart; WindowEnd = [datetime]$Window.WindowEnd; State = 'Planned'; Type = 'Reconciliation' }
                $New[$Row.RowKey] = $Row
                $Rows.Add($Row)
            }

            # 2) The freshest regular window FIRST (so live events alert fast even during a backlog), then the
            #    oldest of whatever remains - regular + reconciliation - to drain gaps before they age out.
            $Due = @($Rows | Where-Object {
                    $_.State -eq 'Planned' -and (-not $_.NextAttemptUtc -or ([datetimeoffset]$_.NextAttemptUtc).UtcDateTime -le $Now)
                } | Sort-Object @{ Expression = { ([datetimeoffset]$_.WindowStart).UtcDateTime } })
            $CurrentWindow = $Due.Where({ [string]$_.RowKey -match '^\d{14}$' }, 'Last', 1)
            $Batch = if ($CurrentWindow.Count -gt 0) {
                $CurrentKey = [string]$CurrentWindow[0].RowKey
                @($CurrentWindow[0]; $Due.Where({ [string]$_.RowKey -ne $CurrentKey }, 'First', $MaxPerCycle - 1))
            } else {
                @($Due.Where({ $true }, 'First', $MaxPerCycle))
            }

            $Plans.Add([pscustomobject]@{ TenantFilter = $TenantFilter; TenantId = [string]$Tenant.TenantId; New = $New; Batch = @($Batch) })
            foreach ($Row in $Batch) {
                $Searches.Add(@{
                        TenantFilter = $TenantFilter
                        RowKey       = [string]$Row.RowKey
                        StartTime    = ([datetimeoffset]$Row.WindowStart).UtcDateTime
                        EndTime      = ([datetimeoffset]$Row.WindowEnd).UtcDateTime
                    })
            }
        } catch {
            Write-Information ('Push-AuditLogSearchCreationV2: could not plan {0}: {1}' -f $TenantFilter, $_.Exception.Message)
        }
    }

    $Results = @{}
    if ($Searches.Count -gt 0) {
        foreach ($Result in (New-CippAuditLogSearchV2 -Searches $Searches.ToArray())) {
            if ($Result) { $Results['{0}|{1}' -f $Result.TenantFilter, $Result.RowKey] = $Result }
        }
    }

    $Created = 0
    foreach ($Plan in $Plans) {
        $TenantFilter = $Plan.TenantFilter
        try {
            $Entities = @{}
            foreach ($Row in $Plan.New.Values) {
                $Entities[$Row.RowKey] = @{
                    PartitionKey = $TenantFilter; RowKey = $Row.RowKey; TenantId = $Plan.TenantId
                    WindowStart = $Row.WindowStart; WindowEnd = $Row.WindowEnd; State = 'Planned'; Type = $Row.Type
                    Attempts = 0; RetryCount = 0; ThrottleCount = 0; SearchId = ''; LastError = ''
                }
            }
            $Disabled = $null
            foreach ($Row in $Plan.Batch) {
                $Result = $Results['{0}|{1}' -f $TenantFilter, $Row.RowKey]
                if (-not $Result) { continue }
                $Entity = $Entities[[string]$Row.RowKey]
                if (-not $Entity) {
                    $Entity = @{ PartitionKey = $TenantFilter; RowKey = [string]$Row.RowKey }
                    $Entities[[string]$Row.RowKey] = $Entity
                }
                if ($Result.Outcome -eq 'Created' -and $Result.Id) {
                    $Entity.State = 'Created'; $Entity.SearchId = [string]$Result.Id; $Entity.Attempts = 0; $Entity.CreatedUtc = $Now
                    $Entity.SearchStatus = [string]$Result.Status; $Entity.LastPolledUtc = $Now
                    $Created++
                } elseif ($Result.Throttled) {
                    $Entity.State = 'Planned'; $Entity.NextAttemptUtc = (Get-CippAuditLogNextAttempt -Attempts 1)
                    $Entity.ThrottleCount = [int]$Row.ThrottleCount + 1; $Entity.LastError = 'Tenant search cap (429)'; $Entity.LastErrorUtc = $Now
                } elseif ($Result.Outcome -eq 'AuditingDisabled' -or $Result.Outcome -eq 'AccessDenied') {
                    $Disabled = $Result
                    $Entity.State = 'Skipped'; $Entity.LastError = if ($Result.Message) { [string]$Result.Message } else { [string]$Result.Status }; $Entity.LastErrorUtc = $Now
                } else {
                    $Attempts = [int]$Row.Attempts + 1
                    $Entity.Attempts = $Attempts; $Entity.RetryCount = [int]$Row.RetryCount + 1
                    $Entity.LastError = [string]$Result.Message; $Entity.LastErrorUtc = $Now
                    if ($Attempts -ge $MaxAttempts) {
                        $Entity.State = 'DeadLetter'
                    } else {
                        $Entity.State = 'Planned'; $Entity.NextAttemptUtc = (Get-CippAuditLogNextAttempt -Attempts $Attempts)
                    }
                }
            }
            if ($Entities.Count -gt 0) {
                Add-CIPPAzDataTableEntity @Ledger -Entity @($Entities.Values) -OperationType UpsertMerge
            }

            if ($Disabled) {
                # AuditingDisabled = unified auditing off; AccessDenied = no token or no audit permission. Disable for 24h.
                $DisableStatus = if ($Disabled.Outcome -eq 'AccessDenied') { [string]$Disabled.Status } else { 'AuditingDisabledTenant' }
                try {
                    $AuditDisabledTable = Get-CIPPTable -TableName 'AuditLogDisabledTenants'
                    Add-CIPPAzDataTableEntity @AuditDisabledTable -Entity @{
                        PartitionKey = 'AuditDisabledTenant'; RowKey = $TenantFilter; TenantFilter = $TenantFilter
                        Status = $DisableStatus; ExpiresAtUnix = [int64]([datetimeoffset]::UtcNow.AddHours(24).ToUnixTimeSeconds())
                    } -Force
                } catch {
                    Write-Information "AuditLogV2: could not record $TenantFilter as disabled: $($_.Exception.Message)"
                }
                Write-Information "AuditLogV2: $DisableStatus for $TenantFilter; disabled for 24h"
                if ($Disabled.Outcome -eq 'AccessDenied') {
                    $LogMessage = if ($Disabled.Message) { [string]$Disabled.Message } else { $DisableStatus }
                    Write-LogMessage -API 'Audit Logs' -tenant $TenantFilter -message "Audit log collection paused for 24 hours: $LogMessage" -sev Warning
                }
            }
        } catch {
            Write-Information ('Push-AuditLogSearchCreationV2: could not record searches for {0}: {1}' -f $TenantFilter, $_.Exception.Message)
        }
    }

    Write-Information "AuditLogV2: created $Created of $($Searches.Count) search(es) for $($Plans.Count) tenant(s)"
    return $true
}
