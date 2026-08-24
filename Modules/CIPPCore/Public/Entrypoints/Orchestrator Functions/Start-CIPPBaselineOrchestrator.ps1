function Start-CIPPBaselineOrchestrator {
    <#
    .SYNOPSIS
        Starts a baseline run: graduation, work-item resolution, one durable job per pair.
    .DESCRIPTION
        The scheduled (12h) baseline entry point, also called directly by ExecBaselineRun for
        on-demand run/compare/oneoff (manual runs carry -Force, so remediation writes even
        when the pre-check shows no drift). Evaluates stage graduations first, then resolves
        the effective (tenant, standard instance) work items from the deltas and fans them
        out as ONE durable wave, each item its own activity (Push-CIPPBaselineStandard).
        The per-tenant license gate lives in the engine (parallel, off the HTTP path), not
        here. No deltas = no-op; the timer itself is gated by the Baselines feature flag.
    .FUNCTIONALITY
        Entrypoint
    #>
    [CmdletBinding()]
    param(
        $TenantFilter,
        $StandardName,
        $TemplateId,
        [ValidateSet('run', 'compare', 'oneoff')]$Mode = 'run',
        $TriggeredBy = 'schedule',
        [switch]$Force
    )

    # A scoped on-demand run should not advance rollouts; the scheduled run does.
    if ($TriggeredBy -eq 'schedule') {
        try { Invoke-CIPPBaselineGraduation } catch { Write-LogMessage -API 'Baselines' -message "Baseline graduation evaluation failed: $($_.Exception.Message)" -Sev 'Error' }
    }

    # The run scope may arrive as a tenant group (the selector sends the group ID) -
    # expand it to the member domains. 'AllTenants'/'allTenants' means no filter at all.
    if ($TenantFilter -in @('AllTenants', 'allTenants')) { $TenantFilter = $null }
    if ($TenantFilter) {
        try {
            $ScopeGroup = Get-TenantGroups | Where-Object { $_.Id -eq $TenantFilter -or $_.Name -eq $TenantFilter } | Select-Object -First 1
            if ($ScopeGroup) { $TenantFilter = @($ScopeGroup.Members.defaultDomainName) }
        } catch {
            Write-Information "Start-CIPPBaselineOrchestrator: tenant group lookup failed: $($_.Exception.Message)"
        }
    }

    $WorkItems = @(Get-CIPPBaselineWorkItems -TenantFilter $TenantFilter -StandardName $StandardName -TemplateId $TemplateId)

    # Scheduled full runs reconcile the resolved store: rows for pairs nothing resolves
    # anymore (standard removed from its baseline, tenant unassigned, override deleted)
    # are cleared so the alignment view never shows stale standards.
    if ($TriggeredBy -eq 'schedule' -and -not ($TenantFilter -or $StandardName -or $TemplateId)) {
        try {
            $ResolvedTable = Get-CippTable -tablename 'BaselineAlignment'
            $ResolvedKeys = @{}
            foreach ($Item in $WorkItems) { $ResolvedKeys[('{0}|{1}' -f $Item.TenantFilter, $Item.Standard)] = $true }
            # One row per (tenant, standard): RowKey is the sanitized standard name.
            # Legacy '<standard>-<templateId>' rows migrate their newest state into the
            # canonical key (preserving triage metadata); pairs nothing resolves anymore
            # are cleared entirely.
            $Orphans = [System.Collections.Generic.List[object]]::new()
            $AllResolved = @(Get-CIPPAzDataTableEntity @ResolvedTable)
            foreach ($Pair in ($AllResolved | Group-Object -Property { '{0}|{1}' -f $_.PartitionKey, $_.StandardName })) {
                if (-not $ResolvedKeys.ContainsKey($Pair.Name)) {
                    foreach ($Row in $Pair.Group) { $Orphans.Add($Row) }
                    continue
                }
                $CanonicalKey = "$($Pair.Group[0].StandardName)" -replace '#', '~'
                $Legacy = @($Pair.Group | Where-Object { $_.RowKey -ne $CanonicalKey })
                if ($Legacy.Count -eq 0) { continue }
                if (@($Pair.Group | Where-Object { $_.RowKey -eq $CanonicalKey }).Count -eq 0) {
                    $Newest = $Legacy | Sort-Object -Property { [int64]($_.LastRun ?? 0) } -Descending | Select-Object -First 1
                    $Migrated = @{}
                    foreach ($Prop in $Newest.PSObject.Properties) {
                        if ($Prop.Name -in @('ETag', 'Timestamp', 'OriginalEntityId')) { continue }
                        $Migrated[$Prop.Name] = $Prop.Value
                    }
                    $Migrated['RowKey'] = $CanonicalKey
                    Add-CIPPAzDataTableEntity @ResolvedTable -Entity $Migrated -Force
                }
                foreach ($Row in $Legacy) { $Orphans.Add($Row) }
            }
            if ($Orphans.Count -gt 0) { Remove-CIPPAzDataTableEntity -Force @ResolvedTable -Entity @($Orphans) }
        } catch {
            Write-Information "Baseline resolved-store reconciliation skipped: $($_.Exception.Message)"
        }
    }

    # 'Disable Scheduled Runs' baselines only execute when an operator runs them. The
    # filter sits AFTER the reconciliation above on purpose: their (tenant, standard)
    # pairs still resolve, so their rows never read as orphans and never get cleaned.
    if ($TriggeredBy -eq 'schedule') {
        $WorkItems = @($WorkItems | Where-Object { -not $_.DisableScheduledRuns })
    }

    if ($WorkItems.Count -eq 0) {
        Write-Information 'Start-CIPPBaselineOrchestrator: no baseline work items resolved - nothing to do.'
        return 0
    }

    # One RunId for the whole orchestration: every log line, history row and queue entry
    # carries it, so a run is traceable end to end. The ambient context stamps the
    # BaselineRunId column onto every log row this invocation writes.
    $RunId = [string](New-Guid).Guid
    Set-CippBaselineRunContext -RunId $RunId

    # Licensing is NOT checked here: the engine gates each (tenant, standard) itself,
    # writing the License Missing row (oneoff bypasses the gate). Doing it in the starter
    # meant one sequential capability lookup per tenant inside the HTTP request - on a
    # large fleet with a cold capability cache, Run Baseline Now took minutes to respond.
    # Reference tags the queue entry so the frontend run tracker can discover the
    # latest baseline run without knowing its id.
    $Queue = New-CippQueueEntry -Name "Baseline $Mode ($($WorkItems.Count) checks) - Run $RunId" -Reference 'BaselineRun' -TotalTasks $WorkItems.Count
    $Batch = foreach ($Item in $WorkItems) {
        [PSCustomObject]@{
            FunctionName = 'CIPPBaselineStandard'
            Item         = $Item
            Mode         = $Mode
            TriggeredBy  = $TriggeredBy
            Force        = [bool]$Force
            RunId        = $RunId
            QueueId      = $Queue.RowKey
            QueueName    = ('{0} - {1}' -f $Item.Standard, $Item.TenantFilter)
        }
    }

    $InputObject = [PSCustomObject]@{
        Batch            = @($Batch)
        OrchestratorName = "BaselineRun_$Mode"
        SkipLog          = $false
        # Right under the audit log pipeline (P2) and ahead of the default 4: a drift
        # check racing a fleet-wide report sweep must not sit behind it for hours, and
        # remediation doubly so.
        Priority         = 3
        # After every check has run, refresh ONLY the caches remediations wrote to -
        # otherwise the next run re-reads stale data and re-detects fixed drift.
        PostExecution    = @{
            FunctionName = 'CIPPBaselineCacheRefresh'
            Parameters   = @{ RunId = $RunId }
        }
    }
    $null = Start-CIPPOrchestrator -InputObject $InputObject
    Write-LogMessage -API 'Baselines' -message "Baseline $Mode started by ${TriggeredBy}: $($WorkItems.Count) (tenant, standard) checks queued - Run $RunId" -Sev 'Info'

    # 90-day history retention (design doc §4.3): prune on the scheduled run only. The newest
    # row per (tenant, standard) partition always survives, even when it is older than 90 days.
    if ($TriggeredBy -eq 'schedule') {
        try {
            $HistoryTable = Get-CippTable -tablename 'BaselineHistory'
            $Cutoff = (Get-Date).AddDays(-90).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ')
            $OldRows = Get-CIPPAzDataTableEntity @HistoryTable -Filter "Timestamp lt datetime'$Cutoff'"
            $Prunable = foreach ($Partition in ($OldRows | Group-Object -Property PartitionKey)) {
                # RowKeys are inverted ticks: the FIRST row sorted ascending is the newest.
                $Sorted = $Partition.Group | Sort-Object -Property RowKey
                $Sorted | Select-Object -Skip 1
            }
            if ($Prunable) { Remove-CIPPAzDataTableEntity -Force @HistoryTable -Entity @($Prunable) }
        } catch {
            Write-Information "Baseline history pruning skipped: $($_.Exception.Message)"
        }
    }

    Set-CippBaselineRunContext -RunId $null
    return $WorkItems.Count
}
