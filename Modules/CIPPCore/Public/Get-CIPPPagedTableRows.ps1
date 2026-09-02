function Get-CIPPPagedTableRows {
    <#
    .FUNCTIONALITY
    Internal
    .SYNOPSIS
    Reads one page of rows from an Azure Table by scanning an ordinal range of partitions.
    .DESCRIPTION
    Continuation-token pager over an ordinal (PartitionKey, RowKey) range: one range query
    per chunk, so page cost tracks rows returned, not partition count. Rows from partitions
    outside $PartitionKeys are dropped but still advance the cursor. A null NextToken means
    the walk is complete.

    Invariants: $PartitionKeys must be ordinal ascending; resume uses RowKey gt '<last>~'
    ('~' sorts after every key character and the '-partN' rows, but an id that prefix-extends
    another id could be skipped at a boundary - GUID ids cannot); -First counts physical
    rows, so only an empty chunk proves the range drained, and the module completes any
    split entity cut at the boundary (RecoverMissingPartRows) so pages hold whole entities.
    .PARAMETER Table
    Table splat from Get-CIPPTable.
    .PARAMETER PartitionKeys
    Partition keys to serve, ordinal ascending; the caller owns membership filtering.
    .PARAMETER RowKeyGe
    Optional inclusive RowKey lower bound (e.g. 'Guests-').
    .PARAMETER RowKeyLt
    Optional exclusive RowKey upper bound (e.g. 'Guests.').
    .PARAMETER ExtraFilterClauses
    Optional OData clauses ANDed onto every query; values must already be escaped.
    .PARAMETER PageSize
    Target kept rows per page (also the physical-row chunk size per query).
    .PARAMETER MaxQueries
    Safety bound on round trips per call; normally one or two are needed.
    .PARAMETER ContinuationToken
    NextToken from the previous call. Opaque to callers.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [hashtable]$Table,
        [Parameter(Mandatory = $true)]
        [AllowEmptyCollection()]
        [string[]]$PartitionKeys,
        [string]$RowKeyGe,
        [string]$RowKeyLt,
        [string[]]$ExtraFilterClauses = @(),
        [ValidateRange(1, 10000)]
        [int]$PageSize = 5000,
        [ValidateRange(1, 100)]
        [int]$MaxQueries = 10,
        [string]$ContinuationToken
    )

    $Rows = [System.Collections.Generic.List[object]]::new()
    if ($PartitionKeys.Count -eq 0) {
        return [PSCustomObject]@{ Rows = $Rows; NextToken = $null }
    }

    $Known = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    foreach ($Pk in $PartitionKeys) { $null = $Known.Add($Pk) }

    $CursorPk = $null
    $CursorRk = $null
    if ($ContinuationToken) {
        $TokenParts = $ContinuationToken.Split('|', 2)
        $CursorPk = [System.Uri]::UnescapeDataString($TokenParts[0])
        if ($TokenParts.Count -eq 2 -and $TokenParts[1]) {
            $CursorRk = [System.Uri]::UnescapeDataString($TokenParts[1])
        }
    }

    $Queries = 0
    $Exhausted = $false
    while (-not $Exhausted -and $Queries -lt $MaxQueries -and $Rows.Count -lt $PageSize) {
        $Clauses = [System.Collections.Generic.List[string]]::new()
        $Clauses.Add("PartitionKey ge '{0}'" -f (ConvertTo-CIPPODataFilterValue -Value $PartitionKeys[0] -Type String))
        $Clauses.Add("PartitionKey le '{0}'" -f (ConvertTo-CIPPODataFilterValue -Value $PartitionKeys[-1] -Type String))
        if ($RowKeyGe) {
            $Clauses.Add("RowKey ge '{0}'" -f (ConvertTo-CIPPODataFilterValue -Value $RowKeyGe -Type String))
        }
        if ($RowKeyLt) {
            $Clauses.Add("RowKey lt '{0}'" -f (ConvertTo-CIPPODataFilterValue -Value $RowKeyLt -Type String))
        }
        if ($CursorPk) {
            $SafePk = ConvertTo-CIPPODataFilterValue -Value $CursorPk -Type String
            if ($CursorRk) {
                $SafeRk = ConvertTo-CIPPODataFilterValue -Value $CursorRk -Type String
                $Clauses.Add("((PartitionKey gt '$SafePk') or (PartitionKey eq '$SafePk' and RowKey gt '$SafeRk~'))")
            } else {
                # A token naming a partition but no row resumes from that partition's start.
                $Clauses.Add("PartitionKey ge '$SafePk'")
            }
        }
        foreach ($Clause in $ExtraFilterClauses) { $Clauses.Add($Clause) }

        $Chunk = @(Get-CIPPAzDataTableEntity @Table -Filter ($Clauses -join ' and ') -First $PageSize)
        $Queries++
        if ($Chunk.Count -eq 0) {
            $Exhausted = $true
            break
        }
        foreach ($Row in $Chunk) {
            if ($Known.Contains([string]$Row.PartitionKey)) { $Rows.Add($Row) }
        }
        $CursorPk = [string]$Chunk[-1].PartitionKey
        $CursorRk = [string]$Chunk[-1].RowKey
    }

    $NextToken = if (-not $Exhausted) {
        '{0}|{1}' -f [System.Uri]::EscapeDataString($CursorPk), $(if ($CursorRk) { [System.Uri]::EscapeDataString($CursorRk) } else { '' })
    } else { $null }

    return [PSCustomObject]@{
        Rows      = $Rows
        NextToken = $NextToken
    }
}
