function Remove-CIPPBecReport {
    <#
    .SYNOPSIS
        Deletes a BEC run: its BecResults row and the BecReports row.
    .DESCRIPTION
        Runs are kept until someone deletes them; there is no automatic retention. Both deletes go
        through the part-aware remover, so a results payload that was split across part rows for
        size leaves nothing behind. The results row goes first so a failed delete never leaves an
        orphaned payload without a run pointing at it.
    .PARAMETER TenantFilter
        Tenant default domain name.
    .PARAMETER CaseId
        The run to delete.
    .FUNCTIONALITY
        Internal
    #>
    [CmdletBinding(SupportsShouldProcess = $true)]
    param(
        [Parameter(Mandatory = $true)][string]$TenantFilter,
        [Parameter(Mandatory = $true)][string]$CaseId
    )

    $Filter = "PartitionKey eq '$($TenantFilter -replace "'", "''")' and RowKey eq '$($CaseId -replace "'", "''")'"
    $Table = Get-CIPPTable -TableName 'BecReports'
    $Row = Get-CIPPAzDataTableEntity @Table -Filter $Filter | Select-Object -First 1
    if (-not $Row) {
        throw "BEC run $CaseId was not found for $TenantFilter"
    }

    $ResultsTable = Get-CIPPTable -TableName 'BecResults'
    $ResultsRow = Get-CIPPAzDataTableEntity @ResultsTable -Filter $Filter | Select-Object -First 1
    if ($ResultsRow -and $PSCmdlet.ShouldProcess("$TenantFilter/$CaseId", 'Delete BEC results row')) {
        $null = Remove-CIPPAzDataTableEntity -Force @ResultsTable -Entity $ResultsRow
    }

    if ($PSCmdlet.ShouldProcess("$TenantFilter/$CaseId", 'Delete BEC run row')) {
        $null = Remove-CIPPAzDataTableEntity -Force @Table -Entity $Row
    }
    return "Deleted BEC run $CaseId for $TenantFilter"
}
