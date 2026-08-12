function Get-CIPPAzDataTableEntity {
    <#
    .FUNCTIONALITY
    Internal
    .SYNOPSIS
    Gets entities from an Azure Table, reassembling entities that were split for size.
    .DESCRIPTION
    Thin wrapper around Get-AzDataTableLargeEntity (AzBobbyTables >= 3.6.2), which
    natively merges rows that were split across multiple properties or rows because
    they exceeded the table service size limits.

    Kept as a wrapper for backward compatibility with existing call sites, to
    default MaxRetries to 3 for throttled requests, and to record entities the
    module could not reassemble.
    #>
    [CmdletBinding()]
    param(
        $Context,
        $Filter,
        $Property,
        $First,
        $Skip,
        $Sort,
        [switch]$Count,
        [int]$MaxRetries = 3
    )

    # ErrorAction and ErrorVariable are set below, so a caller that passed its own would collide
    # with the splat. Real errors are re-emitted afterwards, which honours the caller's preference.
    $Parameters = @{} + $PSBoundParameters
    $Parameters['MaxRetries'] = $MaxRetries
    $null = $Parameters.Remove('ErrorAction')
    $null = $Parameters.Remove('ErrorVariable')

    $Results = Get-AzDataTableLargeEntity @Parameters -ErrorAction SilentlyContinue -ErrorVariable TableErrors

    foreach ($TableError in $TableErrors) {
        # An entity whose rows cannot be reassembled is skipped by the module and reported without
        # failing the query, so one row orphaned by a pre-part-aware delete cannot empty a whole
        # partition. Record which row so it can be removed; pass everything else through.
        if ($TableError.FullyQualifiedErrorId -notlike 'IncompleteEntity*') {
            Write-Error -ErrorRecord $TableError
            continue
        }

        if (-not $script:ReportedIncompleteEntities) {
            $script:ReportedIncompleteEntities = [System.Collections.Generic.HashSet[string]]::new()
        }

        # Write-LogMessage reads a table itself, so logging here re-enters this function. The guard
        # stops that recursing, and the set reports each corrupt row once rather than on every read.
        $RowIdentity = "$($TableError.TargetObject)"
        if ($script:ReportingIncompleteEntity -or -not $script:ReportedIncompleteEntities.Add($RowIdentity)) {
            continue
        }

        $script:ReportingIncompleteEntity = $true
        try {
            Write-LogMessage -API 'Table' -message "Skipped a corrupt table entity. $($TableError.Exception.Message) Delete the orphaned '-partN' rows for '$RowIdentity' to clear this." -Sev 'Error'
        } finally {
            $script:ReportingIncompleteEntity = $false
        }
    }

    $Results
}
