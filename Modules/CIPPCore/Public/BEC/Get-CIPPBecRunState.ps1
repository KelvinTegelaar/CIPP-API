function Get-CIPPBecRunState {
    <#
    .SYNOPSIS
        Reads what the earlier phases of a BEC investigation collected.
    .DESCRIPTION
        Returns one hashtable of every value the phases saved with Set-CIPPBecRunState, applied in
        phase order so a later phase's value (rows re-saved with their IP verdicts, for one) wins.
        Each phase's Completeness markers are merged into one ordered Completeness dictionary.
    .FUNCTIONALITY
        Internal
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][string]$CaseId)

    $Table = Get-CIPPTable -TableName 'BecRunState'
    $State = @{}
    $Completeness = [ordered]@{}
    foreach ($Row in @(Get-CIPPAzDataTableEntity @Table -Filter "PartitionKey eq '$($CaseId -replace "'", "''")'" | Where-Object { $_.Data } | Sort-Object -Property RowKey)) {
        $Values = [string]$Row.Data | ConvertFrom-Json -Depth 20
        foreach ($Property in $Values.PSObject.Properties) {
            if ($Property.Name -eq 'Completeness') {
                foreach ($Marker in @($Property.Value.PSObject.Properties)) { $Completeness[$Marker.Name] = $Marker.Value }
            } else {
                $State[$Property.Name] = $Property.Value
            }
        }
    }
    $State.Completeness = $Completeness
    return $State
}
