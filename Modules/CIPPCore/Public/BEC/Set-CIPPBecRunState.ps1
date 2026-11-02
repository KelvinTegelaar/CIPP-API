function Set-CIPPBecRunState {
    <#
    .SYNOPSIS
        Saves what one phase of a BEC investigation collected, for the phases after it.
    .DESCRIPTION
        Every phase of a run is its own job, so what a phase collects is handed to the later ones
        through the BecRunState table: one row per phase (PartitionKey = case id, RowKey = the
        phase's order and key) holding its values as JSON. Get-CIPPBecRunState reads them back.
        -Clear deletes every row of the case (the start of a run and the end of the last phase).
    .FUNCTIONALITY
        Internal
    #>
    [CmdletBinding(SupportsShouldProcess = $true)]
    param(
        [Parameter(Mandatory = $true)][string]$CaseId,
        [string]$Section,
        [hashtable]$Values,
        [switch]$Clear
    )

    $Table = Get-CIPPTable -TableName 'BecRunState'
    if (-not $PSCmdlet.ShouldProcess($CaseId, $(if ($Clear) { 'Clear BEC run state' } else { "Save BEC run state $Section" }))) { return }
    if ($Clear) {
        # key-only projection: raw head and part rows, which the remover deletes without reassembly
        $Rows = @(Get-CIPPAzDataTableEntity @Table -Filter "PartitionKey eq '$($CaseId -replace "'", "''")'" -Property PartitionKey, RowKey)
        if ($Rows.Count -gt 0) { $null = Remove-CIPPAzDataTableEntity @Table -Entity $Rows -Force }
        return
    }
    Add-CIPPAzDataTableEntity @Table -Entity @{
        PartitionKey = $CaseId
        RowKey       = $Section
        Data         = [string](ConvertTo-Json -InputObject $Values -Depth 20 -Compress)
    } -Force
}
