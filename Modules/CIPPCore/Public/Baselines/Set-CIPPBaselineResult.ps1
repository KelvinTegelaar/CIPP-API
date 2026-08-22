function Set-CIPPBaselineResult {
    <#
    .SYNOPSIS
        Persists one engine result: the columnar BaselineAlignment row + a BaselineHistory row.
    .DESCRIPTION
        The resolved row is the frontend contract (read via Convert-CIPPBaselineResolvedEntity):
        ExpectedValue/CurrentValue/AcceptedPaths/Inheritance as JSON columns, flat PascalCase
        for the rest, StandardName/TenantName/SourceTemplate as view aids. ONE Status column
        (Compliant / Drift / Accepted / Partially Accepted / Denied - Remediate Pending /
        Denied - Delete Pending / Skipped - No License / No Data) - the per-run outcome lives on the
        history rows only. Triage
        metadata (reason/by/at/expires) survives while the status is a triaged one; the engine
        clears it when a row returns to Compliant or plain Drift. History keys
        PK <tenant>_<standard> with an inverted-ticks RowKey so the partition lists
        newest-first. All timestamps are unix seconds.
    .FUNCTIONALITY
        Internal
    #>
    [CmdletBinding()]
    param(
        $Result,
        $Prior,
        $RunId,
        # Free-text explanation for the history timeline (e.g. WHY a run produced No Data).
        [string]$Detail = ''
    )

    $Item = $Result.Item
    $Now = [int64]([datetimeoffset]::UtcNow.ToUnixTimeSeconds())
    if (-not $RunId) { $RunId = [string](New-Guid).Guid }

    # Triaged statuses keep the operator's metadata; Compliant/Drift clears stale triage.
    $KeepTriage = $Result.Status -in @('Accepted', 'Partially Accepted', 'Denied - Remediate Pending', 'Denied - Delete Pending')

    $ResolvedTable = Get-CippTable -tablename 'BaselineAlignment'
    $ResolvedTable.Force = $true
    Add-CIPPAzDataTableEntity @ResolvedTable -Entity @{
        PartitionKey        = "$($Item.TenantFilter)"
        # ONE row per (tenant, standard instance) - never per baseline. A templateId
        # suffix here left a stale row behind whenever ownership changed (baseline B
        # starts configuring a standard baseline A resolved yesterday -> two rows, one
        # Conflict and one stale Compliant). TemplateId stays available as a column.
        RowKey              = ($Item.Standard -replace '#', '~')
        StandardName        = "$($Item.Standard)"
        TenantName          = "$($Item.TenantName)"
        TemplateId          = "$($Item.TemplateId)"
        SourceScope         = "$($Item.SourceScope)"
        SourceTemplate      = "$($Item.SourceTemplate)"
        Stage               = [int]($Item.Stage ?? 1)
        StageName           = "$($Item.StageName)"
        ExpectedValue       = (ConvertTo-Json -Compress -Depth 100 -InputObject $Result.ExpectedValue)
        CurrentValue        = $(if ($null -ne $Result.CurrentValue) { ConvertTo-Json -Compress -Depth 100 -InputObject $Result.CurrentValue } else { $Prior.CurrentValue ?? '' })
        Compliant           = [bool]$Result.Compliant
        PendingVerification = [bool]$Result.PendingVerification
        LicenseAvailable    = [bool]$Result.LicenseAvailable
        Inheritance         = (ConvertTo-Json -Compress -Depth 100 -InputObject @($Result.Inheritance))
        # The engine's per-property deviations (pre-acceptance): the frontend renders
        # these verbatim instead of re-deriving compares - single source of truth.
        Diff                = (ConvertTo-Json -Compress -Depth 100 -InputObject @($Result.RowDiff ?? @()))
        # Manual tasks: the rendered task block, so the UI can show what the operator
        # must do (name, instructions, documentation link).
        Manual              = $(if ($Result.Manual) { ConvertTo-Json -Compress -Depth 20 -InputObject $Result.Manual } else { $Prior.Manual ?? '' })
        AcceptedPaths       = "$($Prior.AcceptedPaths ?? '{}')"
        Status              = "$($Result.Status ?? 'Drift')"
        DeviationReason     = $(if ($KeepTriage) { "$($Prior.DeviationReason)" } else { '' })
        DeviationBy         = $(if ($KeepTriage) { "$($Prior.DeviationBy)" } else { '' })
        DeviationAt         = $(if ($KeepTriage) { $Prior.DeviationAt ?? '' } else { '' })
        DeviationExpires    = $(if ($KeepTriage) { $Prior.DeviationExpires ?? '' } else { '' })
        RemediateOnExpire   = $(if ($KeepTriage) { [bool]$Prior.RemediateOnExpire } else { $false })
        LastRun             = $Now
        LastRemediated      = $(if ($Result.Remediated) { $Now } else { $Prior.LastRemediated ?? '' })
    }

    $HistoryTable = Get-CippTable -tablename 'BaselineHistory'
    $HistoryTable.Force = $true
    $InvertedTicks = '{0:D19}' -f ([DateTime]::MaxValue.Ticks - [DateTime]::UtcNow.Ticks)
    Add-CIPPAzDataTableEntity @HistoryTable -Entity @{
        # '#' is forbidden in Azure Table keys - instance keys sanitize to '~', exactly
        # like the resolved row's RowKey (readers reverse the mapping).
        PartitionKey = ('{0}_{1}' -f $Item.TenantFilter, ($Item.Standard -replace '#', '~'))
        RowKey       = ('{0}-{1}' -f $InvertedTicks, $RunId)
        RunId        = $RunId
        Mode         = "$($Result.Mode)"
        TriggeredBy  = "$($Result.TriggeredBy)"
        Outcome      = "$($Result.Outcome)"
        Remediated   = [bool]$Result.Remediated
        Diff         = $(if ($Result.Diff) { ConvertTo-Json -Compress -Depth 100 -InputObject @($Result.Diff) } else { '' })
        Detail       = "$Detail"
        # Whether this run raises an alert - the timeline shows delivery, not just drift.
        Alerted      = [bool]$Result.AlertEvent
    }
}
