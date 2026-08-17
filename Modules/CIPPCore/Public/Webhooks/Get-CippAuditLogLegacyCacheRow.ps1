function Get-CippAuditLogLegacyCacheRow {
    <#
    .SYNOPSIS
        Read CacheWebhooks rows written before the per-search partitioning change.
    .DESCRIPTION
        Rows written by an older Push-AuditLogDownloadV2 live under PartitionKey = <tenant> and are
        addressable only by an OR-list of RowKeys - a partition scan, the exact pattern the new
        layout removes. Quarantined here rather than left in the hot path.

        CacheWebhooks is transient, so this stops finding anything within a cycle or two. Delete it,
        its caller branch, and the legacy pass in Push-AuditLogProcessingBatchV2 one release on.
    .PARAMETER TenantFilter
        Tenant whose legacy partition is being read.
    .PARAMETER RowIds
        Record ids to fetch.
    .FUNCTIONALITY
        Internal
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$TenantFilter,
        [Parameter(Mandatory = $true)][string[]]$RowIds
    )

    $CacheWebhooksTable = Get-CippTable -TableName 'CacheWebhooks'
    $Results = [System.Collections.Generic.List[object]]::new()

    # Don't raise much above 100: each chunk builds one predicate per row, and an over-long filter
    # is rejected (Azure ~520 predicates, Azurite ~250).
    $ChunkSize = 100
    for ($Offset = 0; $Offset -lt $RowIds.Count; $Offset += $ChunkSize) {
        $Slice = @($RowIds[$Offset..([Math]::Min($Offset + $ChunkSize - 1, $RowIds.Count - 1))])

        # Raw cmdlet: the wrapper merges split parts and reports the logical RowKey.
        $KeyFilter = "PartitionKey eq '$TenantFilter' and (" +
                     (($Slice | ForEach-Object { "RowKey eq '$_'" }) -join ' or ') + ')'
        $Keys = @(Get-AzDataTableEntity @CacheWebhooksTable -Filter $KeyFilter `
                -Property 'PartitionKey', 'RowKey', 'OriginalEntityId')
        if ($Keys.Count -eq 0) { continue }

        # Split records span X / X-part1 / X-part2 and only reassemble when every part arrives in
        # one call, so select on OriginalEntityId rather than RowKey.
        $Predicates = [System.Collections.Generic.List[string]]::new()
        $SeenLogical = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
        foreach ($Key in $Keys) {
            if ($Key.PSObject.Properties.Name -contains 'OriginalEntityId' -and $Key.OriginalEntityId) {
                if ($SeenLogical.Add([string]$Key.OriginalEntityId)) {
                    $Predicates.Add("OriginalEntityId eq '$($Key.OriginalEntityId)'")
                }
            } else {
                $Predicates.Add("RowKey eq '$($Key.RowKey)'")
            }
        }
        if ($Predicates.Count -eq 0) { continue }

        # No -Property: a projection must list every JSON_Part* column or split rows come back empty.
        $RowFilter = "PartitionKey eq '$TenantFilter' and (" + ($Predicates -join ' or ') + ')'
        foreach ($Entity in @(Get-CIPPAzDataTableEntity @CacheWebhooksTable -Filter $RowFilter)) {
            $Results.Add($Entity)
        }
    }

    return $Results.ToArray()
}
