function Get-CIPPBecReport {
    <#
    .SYNOPSIS
        Reads BEC run rows from the BecReports table, optionally with the results payload.
    .DESCRIPTION
        Without -CaseId, lists the run rows for a tenant (or every tenant with -TenantFilter AllTenants),
        optionally narrowed to one user - metadata only, newest first. With -CaseId, returns that
        single run and, when -IncludeResults is set, fetches the run's row from the BecResults table
        (reassembled from its part rows when the payload was split for size) and attaches the parsed
        payload as the Results property. Everything comes from table storage.
    .PARAMETER TenantFilter
        Tenant default domain name, or AllTenants.
    .PARAMETER CaseId
        A specific run.
    .PARAMETER UserId
        Narrow the list to one user's runs.
    .PARAMETER IncludeResults
        Fetch and attach the results payload (single run only).
    .FUNCTIONALITY
        Internal
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$TenantFilter,
        [string]$CaseId,
        [string]$UserId,
        [switch]$IncludeResults
    )

    $Table = Get-CIPPTable -TableName 'BecReports'
    $Clauses = [System.Collections.Generic.List[string]]::new()
    if ($TenantFilter -ne 'AllTenants') {
        $Clauses.Add("PartitionKey eq '$($TenantFilter -replace "'", "''")'")
    }
    if ($CaseId) {
        $Clauses.Add("RowKey eq '$($CaseId -replace "'", "''")'")
    }
    if ($UserId) {
        $Clauses.Add("UserId eq '$($UserId -replace "'", "''")'")
    }
    $Rows = if ($Clauses.Count -gt 0) {
        Get-CIPPAzDataTableEntity @Table -Filter ($Clauses -join ' and ')
    } else {
        Get-CIPPAzDataTableEntity @Table
    }
    $Rows = @($Rows | Where-Object { $_ } | Sort-Object -Property RowKey -Descending)
    foreach ($Row in $Rows) {
        foreach ($JsonProp in @('Containment')) {
            if ($Row.PSObject.Properties[$JsonProp] -and $Row.$JsonProp -is [string] -and $Row.$JsonProp) {
                # @() because ConvertFrom-Json unrolls a JSON array: a one-entry history would come back as a bare object
                try { $Row.$JsonProp = @($Row.$JsonProp | ConvertFrom-Json -ErrorAction Stop) } catch { Write-Verbose "BEC run $($Row.RowKey): $JsonProp is not valid JSON, leaving it as text" }
            }
        }
        $Row | Add-Member -NotePropertyName 'CaseId' -NotePropertyValue $Row.RowKey -Force
        $Row | Add-Member -NotePropertyName 'Tenant' -NotePropertyValue $Row.PartitionKey -Force
    }
    if ($CaseId) {
        $Row = $Rows | Select-Object -First 1
        # Only a completed run has a results payload; a queued, running or failed run has nothing
        # to attach and must not be treated as broken.
        if ($Row -and $IncludeResults -and $Row.Status -eq 'Completed') {
            $ResultsTable = Get-CIPPTable -TableName 'BecResults'
            $ResultsRow = Get-CIPPAzDataTableEntity @ResultsTable -Filter "PartitionKey eq '$($Row.PartitionKey -replace "'", "''")' and RowKey eq '$($Row.RowKey -replace "'", "''")'" | Select-Object -First 1
            if ($ResultsRow -and $ResultsRow.Results) {
                $Row | Add-Member -NotePropertyName 'Results' -NotePropertyValue ([string]$ResultsRow.Results | ConvertFrom-Json -Depth 20) -Force
            } else {
                throw "The results payload for case $CaseId was not found in the BecResults table"
            }
        }
        return $Row
    }
    return $Rows
}
