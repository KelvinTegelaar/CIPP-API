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
    .PARAMETER Kind
        BEC (BecReports, BecResults) or NHI, a non-human identity investigation (NhiReports, NhiResults).
    .FUNCTIONALITY
        Internal
    #>
    [CmdletBinding(SupportsShouldProcess = $true)]
    param(
        [Parameter(Mandatory = $true)][string]$TenantFilter,
        [Parameter(Mandatory = $true)][string]$CaseId,
        [ValidateSet('BEC', 'NHI')][string]$Kind = 'BEC'
    )
    $TablePrefix = if ($Kind -eq 'NHI') { 'Nhi' } else { 'Bec' }

    $Filter = "PartitionKey eq '$($TenantFilter -replace "'", "''")' and RowKey eq '$($CaseId -replace "'", "''")'"
    $Table = Get-CIPPTable -TableName "$($TablePrefix)Reports"
    $Row = Get-CIPPAzDataTableEntity @Table -Filter $Filter | Select-Object -First 1
    if (-not $Row) {
        throw [System.Management.Automation.ItemNotFoundException]::new("$Kind run $CaseId was not found for $TenantFilter")
    }

    $ResultsTable = Get-CIPPTable -TableName "$($TablePrefix)Results"
    $ResultsRow = Get-CIPPAzDataTableEntity @ResultsTable -Filter $Filter | Select-Object -First 1
    if ($ResultsRow -and $PSCmdlet.ShouldProcess("$TenantFilter/$CaseId", 'Delete BEC results row')) {
        $null = Remove-CIPPAzDataTableEntity -Force @ResultsTable -Entity $ResultsRow
    }

    if ($PSCmdlet.ShouldProcess("$TenantFilter/$CaseId", 'Delete BEC run row')) {
        $null = Remove-CIPPAzDataTableEntity -Force @Table -Entity $Row
    }
    return "Deleted $Kind run $CaseId for $TenantFilter"
}
