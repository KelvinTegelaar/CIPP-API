function Start-CIPPBaselineOrchestrator {
    <#
    .SYNOPSIS
        Starts a baseline run: graduation, work-item resolution, one durable job per pair.
    .DESCRIPTION
        The scheduled (12h) baseline entry point, also called directly by ExecBaselineRun for
        on-demand run/compare/oneoff (manual runs carry -Force, so remediation writes even
        when the pre-check shows no drift). Evaluates stage graduations first, then resolves
        the effective (tenant, standard instance) work items from the deltas, strips the pairs
        the tenant is not licensed for - writing a License Missing resolved row so the feedback
        shows - and fans the rest out as ONE durable wave, each item its own activity
        (Push-CIPPBaselineStandard). No deltas = no-op; the timer itself is gated by the
        Baselines feature flag.
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

    $WorkItems = @(Get-CIPPBaselineWorkItems -TenantFilter $TenantFilter -StandardName $StandardName -TemplateId $TemplateId)

    # Scheduled full runs reconcile the resolved store: rows for pairs nothing resolves
    # anymore (standard removed from its baseline, tenant unassigned, override deleted)
    # are cleared so the alignment view never shows stale standards.
    if ($TriggeredBy -eq 'schedule' -and -not ($TenantFilter -or $StandardName -or $TemplateId)) {
        try {
            $ResolvedTable = Get-CippTable -tablename 'BaselineAlignment'
            $ResolvedKeys = @{}
            foreach ($Item in $WorkItems) { $ResolvedKeys[('{0}|{1}' -f $Item.TenantFilter, $Item.Standard)] = $true }
            $Orphans = @(Get-CIPPAzDataTableEntity @ResolvedTable | Where-Object { -not $ResolvedKeys.ContainsKey(('{0}|{1}' -f $_.PartitionKey, $_.StandardName)) })
            if ($Orphans) { Remove-CIPPAzDataTableEntity -Force @ResolvedTable -Entity $Orphans }
        } catch {
            Write-Information "Baseline resolved-store reconciliation skipped: $($_.Exception.Message)"
        }
    }

    if ($WorkItems.Count -eq 0) {
        Write-Information 'Start-CIPPBaselineOrchestrator: no baseline work items resolved - nothing to do.'
        return 0
    }

    # License prefilter: collect each item's required capabilities, compare against the
    # tenant's licenses ONCE per tenant, and strip unlicensed pairs before anything runs.
    # The stripped pairs still get a License Missing resolved row so the tenant view shows
    # why. A oneoff is an explicit operator ask and skips the strip - the capability cache
    # may not know about a license bought after the last sync.
    $Definitions = Get-CIPPBaselineDefinition
    $CapabilitiesByTenant = @{}
    $LicensedItems = [System.Collections.Generic.List[object]]::new()
    foreach ($Item in $WorkItems) {
        $Definition = $Definitions | Where-Object { $_.name -eq $Item.BaseName } | Select-Object -First 1
        $Required = @($Definition.requiredCapabilities)
        $Licensed = $true
        if ($Required.Count -gt 0 -and $Mode -ne 'oneoff') {
            if (-not $CapabilitiesByTenant.ContainsKey($Item.TenantFilter)) {
                $CapabilitiesByTenant[$Item.TenantFilter] = $(try { Get-CIPPTenantCapabilities -TenantFilter $Item.TenantFilter } catch { $null })
            }
            $Capabilities = $CapabilitiesByTenant[$Item.TenantFilter]
            $Licensed = @($Required | Where-Object { $Capabilities.$_ -eq $true }).Count -gt 0
        }
        if ($Licensed) {
            $LicensedItems.Add($Item)
        } else {
            try {
                Set-CIPPBaselineResult -Prior $null -Result ([PSCustomObject]@{
                        Item                = $Item
                        Mode                = $Mode
                        TriggeredBy         = $TriggeredBy
                        ExpectedValue       = $null
                        CurrentValue        = $null
                        Compliant           = $false
                        PendingVerification = $false
                        LicenseAvailable    = $false
                        Status              = 'Skipped - No License'
                        Remediated          = $false
                        Outcome             = 'Skipped-License'
                        Diff                = $null
                        Inheritance         = @($Item.Tiers)
                        AlertEvent          = $null
                    })
            } catch {
                Write-Information "Baselines: failed to record License Missing for $($Item.Standard) on $($Item.TenantFilter): $($_.Exception.Message)"
            }
        }
    }
    if ($LicensedItems.Count -eq 0) {
        Write-Information 'Start-CIPPBaselineOrchestrator: no licensed work items remain - nothing to queue.'
        return 0
    }

    $Queue = New-CippQueueEntry -Name "Baseline $Mode ($($LicensedItems.Count) checks)" -TotalTasks $LicensedItems.Count
    $Batch = foreach ($Item in $LicensedItems) {
        [PSCustomObject]@{
            FunctionName = 'CIPPBaselineStandard'
            Item         = $Item
            Mode         = $Mode
            TriggeredBy  = $TriggeredBy
            Force        = [bool]$Force
            QueueId      = $Queue.RowKey
            QueueName    = ('{0} - {1}' -f $Item.Standard, $Item.TenantFilter)
        }
    }

    $InputObject = [PSCustomObject]@{
        Batch            = @($Batch)
        OrchestratorName = "BaselineRun_$Mode"
        SkipLog          = $false
        # After every check has run, refresh ONLY the caches remediations wrote to -
        # otherwise the next run re-reads stale data and re-detects fixed drift.
        PostExecution    = @{
            FunctionName = 'CIPPBaselineCacheRefresh'
        }
    }
    $null = Start-CIPPOrchestrator -InputObject $InputObject
    Write-LogMessage -API 'Baselines' -message "Baseline $Mode started: $($LicensedItems.Count) (tenant, standard) checks queued." -Sev 'Info'

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

    return $LicensedItems.Count
}
