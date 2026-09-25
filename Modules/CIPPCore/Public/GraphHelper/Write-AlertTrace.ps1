function Write-AlertTrace {
    <#
    .SYNOPSIS
        Reconcile one alert run against the AlertLifecycle table and return the items worth notifying about.
    .DESCRIPTION
        Every scripted alert (Get-CIPPAlert*) calls this once per tenant with everything it found,
        including an empty result when it found nothing. Each item is hashed with
        Get-AlertContentHash and compared with the rows already stored for this cmdlet and tenant:

          - not stored yet                 -> New       (Open, or Snoozed when a snooze covers it)
          - stored and Resolved            -> Reopened  (ReopenCount + 1)
          - stored and still present       -> Continuing (LastSeen refreshed, no notification)
          - stored but absent this run     -> Resolved
          - stored as Snoozed, snooze gone -> back to Open and notified again

        Only New and Reopened items that are not snoozed are returned, so the scheduled-task
        post-execution step notifies once per state change instead of once per run. A run that
        finds nothing returns nothing and resolves whatever was still open.

        A snooze set "until resolved" is deleted when its item resolves, so the item notifies
        again if it ever comes back. Timed snoozes outlive a resolution and keep suppressing
        the item until they expire.

        Alerts that fail part-way must not call this, since "could not check" is not "clear".

        With -Append the run is treated as a stream of events rather than a full picture: items
        are added or refreshed but nothing is resolved by absence. Open rows that have not been
        seen for 30 days are resolved as stale instead.
    .FUNCTIONALITY
        Internal
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        $cmdletName,
        $data,
        [Parameter(Mandatory = $true)]
        $tenantFilter,
        [string]$AlertComment = $null,
        [switch]$Append
    )

    $CmdletName = [string]$cmdletName
    $TenantFilter = [string]$tenantFilter
    $Now = [datetime]::UtcNow
    $NowIso = $Now.ToString('o')
    $StaleCutoff = $Now.AddDays(-30)
    $RetentionCutoff = $Now.AddDays(-90)

    $Table = Get-CIPPTable -tablename 'AlertLifecycle'
    $SafeTenant = ConvertTo-CIPPODataFilterValue -Value $TenantFilter -Type String
    $SafeCmdlet = ConvertTo-CIPPODataFilterValue -Value $CmdletName -Type String
    $Existing = @(Get-CIPPAzDataTableEntity @Table -Filter "PartitionKey eq '$SafeTenant' and CmdletName eq '$SafeCmdlet'")

    $ByHash = @{}
    foreach ($Row in $Existing) {
        if ($Row.ContentHash) { $ByHash[[string]$Row.ContentHash] = $Row }
    }

    # One-time seed: the first reconcile for a cmdlet/tenant pair after the upgrade treats the
    # items of its last AlertLastRun row as already open, so nothing that was already known
    # is announced as new.
    if ($Existing.Count -eq 0) {
        try {
            $LastRunTable = Get-CIPPTable -tablename 'AlertLastRun'
            $SafeLastRunKey = ConvertTo-CIPPODataFilterValue -Value "$($TenantFilter)-$($CmdletName)" -Type String
            $LastRunRows = @(Get-CIPPAzDataTableEntity @LastRunTable -Filter "RowKey eq '$SafeLastRunKey'")
            $LastRun = $LastRunRows | Where-Object { $_.PartitionKey -match '^\d{8}$' } | Sort-Object -Property PartitionKey -Descending | Select-Object -First 1
            if ($LastRun -and -not [string]::IsNullOrWhiteSpace($LastRun.LogData)) {
                $SeedSeen = [datetime]::ParseExact([string]$LastRun.PartitionKey, 'yyyyMMdd', [cultureinfo]::InvariantCulture).ToString('o')
                foreach ($SeedItem in @($LastRun.LogData | ConvertFrom-Json -ErrorAction Stop)) {
                    if ($null -eq $SeedItem) { continue }
                    $SeedHash = Get-AlertContentHash -AlertItem $SeedItem
                    if ($ByHash.ContainsKey($SeedHash.ContentHash)) { continue }
                    $SeedKeys = Get-CIPPAlertLifecycleKey -CmdletName $CmdletName -TenantFilter $TenantFilter -ContentHash $SeedHash.ContentHash
                    $ByHash[$SeedHash.ContentHash] = [PSCustomObject]@{
                        PartitionKey        = $SeedKeys.PartitionKey
                        RowKey              = $SeedKeys.RowKey
                        CmdletName          = $CmdletName
                        Tenant              = $TenantFilter
                        ContentHash         = $SeedHash.ContentHash
                        ContentPreview      = $SeedHash.ContentPreview
                        AlertItem           = [string](ConvertTo-Json -InputObject $SeedItem -Compress -Depth 10)
                        AlertComment        = [string]$LastRun.AlertComment
                        Status              = 'Open'
                        FirstSeen           = $SeedSeen
                        LastSeen            = $SeedSeen
                        LastChecked         = $SeedSeen
                        ResolvedAt          = ''
                        ReopenCount         = '0'
                        SnoozeUntil         = ''
                        SnoozedBy           = ''
                        SnoozeRowKey        = ''
                        SnoozeReason        = ''
                        SnoozeVisible       = ''
                        SnoozeUntilResolved = ''
                    }
                }
                Write-Information "Seeded $($ByHash.Count) open alert items for $CmdletName / $TenantFilter from AlertLastRun"
            }
        } catch {
            Write-Information "Could not seed AlertLifecycle from AlertLastRun for $CmdletName / $TenantFilter : $($_.Exception.Message)"
        }
    }

    $Snoozes = Get-CIPPActiveAlertSnoozes -CmdletName $CmdletName -TenantFilter $TenantFilter

    $Seen = [System.Collections.Generic.HashSet[string]]::new()
    $Writes = [System.Collections.Generic.List[object]]::new()
    $Notify = [System.Collections.Generic.List[object]]::new()
    $Counts = @{ New = 0; Reopened = 0; Continuing = 0; Resolved = 0; Snoozed = 0 }

    foreach ($Item in @($data)) {
        if ($null -eq $Item) { continue }
        $Hash = Get-AlertContentHash -AlertItem $Item
        if (-not $Seen.Add($Hash.ContentHash)) { continue }

        $Snooze = $Snoozes[$Hash.ContentHash]
        $Keys = Get-CIPPAlertLifecycleKey -CmdletName $CmdletName -TenantFilter $TenantFilter -ContentHash $Hash.ContentHash
        $ItemJson = [string](ConvertTo-Json -InputObject $Item -Compress -Depth 10)
        $Row = $ByHash[$Hash.ContentHash]

        $Entity = @{
            PartitionKey        = $Keys.PartitionKey
            RowKey              = $Keys.RowKey
            CmdletName          = $CmdletName
            Tenant              = $TenantFilter
            ContentHash         = [string]$Hash.ContentHash
            ContentPreview      = [string]$Hash.ContentPreview
            AlertItem           = $ItemJson
            AlertComment        = [string]$AlertComment
            LastSeen            = $NowIso
            LastChecked         = $NowIso
            ResolvedAt          = ''
            SnoozeUntil         = if ($Snooze) { [string]$Snooze.SnoozeUntil } else { '' }
            SnoozedBy           = if ($Snooze) { [string]$Snooze.SnoozedBy } else { '' }
            SnoozeRowKey        = if ($Snooze) { [string]$Snooze.RowKey } else { '' }
            SnoozeReason        = if ($Snooze) { [string]$Snooze.SnoozeReason } else { '' }
            SnoozeVisible       = if ($Snooze) { [string]([string]$Snooze.KeepVisible -eq 'True') } else { '' }
            SnoozeUntilResolved = if ($Snooze) { [string]([string]$Snooze.UntilResolved -eq 'True') } else { '' }
        }

        if (-not $Row) {
            $Entity.Status = if ($Snooze) { 'Snoozed' } else { 'Open' }
            $Entity.FirstSeen = $NowIso
            $Entity.ReopenCount = '0'
            if ($Snooze) { $Counts.Snoozed++ } else { $Counts.New++; $Notify.Add($Item) }
        } else {
            $PriorStatus = [string]$Row.Status
            $Entity.FirstSeen = [string]$Row.FirstSeen
            $Entity.ReopenCount = [string]([int]($Row.ReopenCount ?? 0))

            if ($PriorStatus -eq 'Resolved') {
                $Entity.Status = if ($Snooze) { 'Snoozed' } else { 'Open' }
                $Entity.FirstSeen = $NowIso
                $Entity.ReopenCount = [string]([int]($Row.ReopenCount ?? 0) + 1)
                if ($Snooze) { $Counts.Snoozed++ } else { $Counts.Reopened++; $Notify.Add($Item) }
            } elseif ($Snooze) {
                $Entity.Status = 'Snoozed'
                $Counts.Snoozed++
            } elseif ($PriorStatus -eq 'Snoozed') {
                # The snooze lapsed or was removed while the condition persisted: it fires again.
                $Entity.Status = 'Open'
                $Counts.New++
                $Notify.Add($Item)
            } else {
                $Entity.Status = 'Open'
                $Counts.Continuing++
            }
        }

        $Writes.Add($Entity)
    }

    $Removals = [System.Collections.Generic.List[object]]::new()
    $SnoozesToDrop = [System.Collections.Generic.List[object]]::new()
    foreach ($Row in $Existing) {
        if ($Seen.Contains([string]$Row.ContentHash)) { continue }
        $Status = [string]$Row.Status

        if ($Status -eq 'Resolved') {
            [datetime]$ResolvedAt = [datetime]::MinValue
            if ([datetime]::TryParse([string]$Row.ResolvedAt, [cultureinfo]::InvariantCulture, [System.Globalization.DateTimeStyles]::RoundtripKind, [ref]$ResolvedAt) -and $ResolvedAt -lt $RetentionCutoff) {
                $Removals.Add($Row)
            }
            continue
        }

        $ResolveIt = $true
        if ($Append) {
            [datetime]$LastSeen = [datetime]::MinValue
            $ResolveIt = [datetime]::TryParse([string]$Row.LastSeen, [cultureinfo]::InvariantCulture, [System.Globalization.DateTimeStyles]::RoundtripKind, [ref]$LastSeen) -and $LastSeen -lt $StaleCutoff
        }
        if (-not $ResolveIt) { continue }

        # Rewrite the whole row: the upsert replaces rather than merges.
        $Resolved = @{}
        foreach ($Prop in $Row.PSObject.Properties) {
            if ($Prop.Name -in @('ETag', 'Timestamp')) { continue }
            $Resolved[$Prop.Name] = $Prop.Value
        }
        $Resolved.Status = 'Resolved'
        $Resolved.ResolvedAt = $NowIso
        $Resolved.LastChecked = $NowIso
        if ($Status -eq 'Snoozed' -and [string]$Row.SnoozeUntilResolved -eq 'True') {
            # An "until resolved" snooze has done its job; drop it so a comeback notifies again.
            $SnoozesToDrop.Add([string]$Row.SnoozeRowKey)
            $Resolved.SnoozeUntil = ''
            $Resolved.SnoozedBy = ''
            $Resolved.SnoozeRowKey = ''
            $Resolved.SnoozeReason = ''
            $Resolved.SnoozeVisible = ''
            $Resolved.SnoozeUntilResolved = ''
        }
        $Writes.Add($Resolved)
        $Counts.Resolved++
    }

    if ($Writes.Count -gt 0) {
        Add-CIPPAzDataTableEntity @Table -Entity @($Writes) -Force | Out-Null
    }
    if ($Removals.Count -gt 0) {
        try {
            foreach ($Old in $Removals) {
                Remove-CIPPAzDataTableEntity @Table -Entity @{
                    PartitionKey = [string]$Old.PartitionKey
                    RowKey       = [string]$Old.RowKey
                    ETag         = '*'
                } | Out-Null
            }
        } catch {
            Write-Information "Could not purge resolved alert rows for $CmdletName / $TenantFilter : $($_.Exception.Message)"
        }
    }
    if ($SnoozesToDrop.Count -gt 0) {
        try {
            $SnoozeTable = Get-CIPPTable -tablename 'AlertSnooze'
            foreach ($SnoozeKey in $SnoozesToDrop) {
                if ([string]::IsNullOrWhiteSpace($SnoozeKey)) { continue }
                Remove-CIPPAzDataTableEntity @SnoozeTable -Entity @{
                    PartitionKey = $CmdletName
                    RowKey       = $SnoozeKey
                    ETag         = '*'
                } | Out-Null
            }
        } catch {
            Write-Information "Could not drop until-resolved snoozes for $CmdletName / $TenantFilter : $($_.Exception.Message)"
        }
    }

    Write-Information ("Alert reconcile for {0} / {1}: {2} new, {3} reopened, {4} continuing, {5} resolved, {6} snoozed" -f $CmdletName, $TenantFilter, $Counts.New, $Counts.Reopened, $Counts.Continuing, $Counts.Resolved, $Counts.Snoozed)

    if ($Notify.Count -gt 0) {
        return @($Notify)
    }
    return $null
}
