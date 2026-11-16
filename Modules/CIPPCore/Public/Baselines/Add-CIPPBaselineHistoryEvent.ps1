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
        A scheduled run whose outcome, diff and detail match the partition's newest row
        extends that row (RunCount, LastRunAt, LastRunId) instead of adding one; manual
        runs, remediations, alerts and every non-run event always get their own row.
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
        [bool]$Remediated = $false,
        [bool]$Alerted = $false
    )

    if (-not $RunId) { $RunId = [string](New-Guid).Guid }
    $HistoryTable = Get-CippTable -tablename 'BaselineHistory'
    # '#' is forbidden in Azure Table keys - instance keys sanitize to '~', exactly like run rows (readers reverse the mapping).
    $PartitionKey = '{0}_{1}' -f $TenantFilter, ("$Standard" -replace '#', '~')
    $DiffJson = $(if ($Diff) { ConvertTo-Json -Compress -Depth 100 -InputObject @($Diff) } else { '' })
    $Fingerprint = [Convert]::ToHexString([System.Security.Cryptography.SHA256]::HashData([System.Text.Encoding]::UTF8.GetBytes("$Outcome|$DiffJson|$Detail")))

    if ($Mode -in @('run', 'compare') -and $TriggeredBy -in @('schedule', 'verification') -and -not $Remediated -and -not $Alerted) {
        $SafePartition = ConvertTo-CIPPODataFilterValue -Value $PartitionKey
        $Latest = Get-AzDataTableEntity @HistoryTable -Filter "PartitionKey eq '$SafePartition'" -Property @('PartitionKey', 'RowKey', 'Fingerprint', 'RunCount', 'TriggeredBy') -First 1
        if ($Latest -and $Latest.Fingerprint -eq $Fingerprint -and $Latest.TriggeredBy -in @('schedule', 'verification')) {
            try {
                Update-CIPPAzDataTableEntity @HistoryTable -Force -Entity @{
                    PartitionKey = $Latest.PartitionKey
                    RowKey       = $Latest.RowKey
                    RunCount     = [int]($Latest.RunCount ?? 1) + 1
                    LastRunAt    = [int64]([datetimeoffset]::UtcNow.ToUnixTimeSeconds())
                    LastRunId    = "$RunId"
                }
                return $RunId
            } catch {
                Write-Information "Baseline history: extending $PartitionKey failed, writing a new row: $($_.Exception.Message)"
            }
        }
    }

    $InvertedTicks = '{0:D19}' -f ([DateTime]::MaxValue.Ticks - [DateTime]::UtcNow.Ticks)
    Add-CIPPAzDataTableEntity @HistoryTable -Force -Entity @{
        PartitionKey = $PartitionKey
        RowKey       = ('{0}-{1}' -f $InvertedTicks, $RunId)
        RunId        = "$RunId"
        Mode         = "$Mode"
        TriggeredBy  = "$TriggeredBy"
        Outcome      = "$Outcome"
        Remediated   = $Remediated
        Alerted      = $Alerted
        Diff         = $DiffJson
        Detail       = "$Detail"
        Fingerprint  = $Fingerprint
        RunCount     = 1
    }
    $RunId
}
