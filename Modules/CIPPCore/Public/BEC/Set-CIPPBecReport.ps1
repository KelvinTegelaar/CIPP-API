function Set-CIPPBecReport {
    <#
    .SYNOPSIS
        Writes or updates a BEC run: the row in the BecReports table and, optionally, its results row.
    .DESCRIPTION
        One row per run (PartitionKey = tenant default domain, RowKey = case id) holds the small,
        listable metadata - user, status, scope, score, timestamps, containment history, evidence
        export records. The full results payload goes to its own row in the BecResults table (same
        keys) so history lists never read megabytes of JSON; the large-entity writer splits an
        oversized payload across part rows transparently and cleans stale parts up when a rewritten
        payload shrinks. Row properties are merged (UpsertMerge): a status/score update does not
        clobber the containment history another request appended, and null values are dropped
        before the write. Everything lives in table storage; nothing is written to blobs.
    .PARAMETER TenantFilter
        Tenant default domain name.
    .PARAMETER CaseId
        The run's case id.
    .PARAMETER Properties
        Hashtable of row properties to set/merge (Status, Score, Level, UserId, ...).
    .PARAMETER Results
        When supplied, serialised to JSON and written to the run's BecResults row (replace).
    .PARAMETER Replace
        Replace the whole run row instead of merging (used when a run is first created).
    .FUNCTIONALITY
        Internal
    #>
    [CmdletBinding(SupportsShouldProcess = $true)]
    param(
        [Parameter(Mandatory = $true)][string]$TenantFilter,
        [Parameter(Mandatory = $true)][string]$CaseId,
        [hashtable]$Properties = @{},
        $Results,
        [switch]$Replace
    )

    $Entity = @{
        PartitionKey = [string]$TenantFilter
        RowKey       = [string]$CaseId
    }
    foreach ($Key in $Properties.Keys) {
        $Value = $Properties[$Key]
        if ($null -eq $Value) { continue }
        # Table properties are scalars; anything structured is stored as compact JSON.
        if ($Value -is [string] -or $Value -is [bool] -or $Value -is [int] -or $Value -is [long] -or $Value -is [double] -or $Value -is [datetime] -or $Value -is [guid]) {
            $Entity[$Key] = $Value
        } else {
            $Entity[$Key] = [string](ConvertTo-Json -InputObject $Value -Depth 15 -Compress)
        }
    }

    if ($PSBoundParameters.ContainsKey('Results') -and $null -ne $Results) {
        $Json = ConvertTo-Json -InputObject $Results -Depth 15 -Compress
        $ResultsTable = Get-CIPPTable -TableName 'BecResults'
        if ($PSCmdlet.ShouldProcess("$TenantFilter/$CaseId", 'Write BEC results row')) {
            Add-CIPPAzDataTableEntity @ResultsTable -Entity @{
                PartitionKey = [string]$TenantFilter
                RowKey       = [string]$CaseId
                Results      = $Json
            } -Force
        }
    }

    $Table = Get-CIPPTable -TableName 'BecReports'
    if ($PSCmdlet.ShouldProcess("$TenantFilter/$CaseId", 'Write BEC run row')) {
        if ($Replace) {
            Add-CIPPAzDataTableEntity @Table -Entity $Entity -Force
        } else {
            Add-CIPPAzDataTableEntity @Table -Entity $Entity -OperationType UpsertMerge
        }
    }
    return $Entity
}
