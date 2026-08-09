function Add-CIPPBaselineHistoryEvent {
    <#
    .SYNOPSIS
        Appends one operator/system event to the BaselineHistory audit trail.
    .DESCRIPTION
        Engine runs write their history through Set-CIPPBaselineResult; everything else
        that changes baseline state writes through here so the timeline is a complete
        audit trail: triage verdicts (accept/deny/clear, whole-row and per-path),
        overrides, manual and automatic stage advances, task completions, and the
        deletions carried out for denied deviations. Same schema and keying as run
        rows (PK <tenant>_<standard~>, inverted-ticks RowKey → newest-first), so the
        history reader needs no second source; Mode distinguishes the event class
        ('triage' | 'stage' | 'delete') from engine runs ('run' | 'compare' | 'oneoff').
        Detail is the one-line human story ("Accepted: change ticket #123"); Diff is
        optional structured data rendered like a run diff.
    .FUNCTIONALITY
        Internal
    #>
    [CmdletBinding()]
    param(
        $TenantFilter,
        $Standard,
        $Mode,
        $TriggeredBy,
        $Outcome,
        $Detail,
        $Diff,
        $RunId,
        [bool]$Remediated = $false
    )

    if (-not $RunId) { $RunId = [string](New-Guid).Guid }
    $HistoryTable = Get-CippTable -tablename 'BaselineHistory'
    $HistoryTable.Force = $true
    $InvertedTicks = '{0:D19}' -f ([DateTime]::MaxValue.Ticks - [DateTime]::UtcNow.Ticks)
    Add-CIPPAzDataTableEntity @HistoryTable -Entity @{
        # '#' is forbidden in Azure Table keys - instance keys sanitize to '~', exactly
        # like run rows (readers reverse the mapping).
        PartitionKey = ('{0}_{1}' -f $TenantFilter, ("$Standard" -replace '#', '~'))
        RowKey       = ('{0}-{1}' -f $InvertedTicks, $RunId)
        RunId        = "$RunId"
        Mode         = "$Mode"
        TriggeredBy  = "$TriggeredBy"
        Outcome      = "$Outcome"
        Remediated   = $Remediated
        Diff         = $(if ($Diff) { ConvertTo-Json -Compress -Depth 100 -InputObject @($Diff) } else { '' })
        Detail       = "$Detail"
    }
    $RunId
}
