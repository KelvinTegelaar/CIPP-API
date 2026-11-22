function Get-CIPPBecRunState {
    <#
    .SYNOPSIS
        Reads what the earlier phases of a BEC investigation collected.
    .DESCRIPTION
        Returns one hashtable of every value the phases saved with Set-CIPPBecRunState, applied in
        phase order so a later phase's value (rows re-saved with their IP verdicts, for one) wins.
        Each phase's Completeness markers are merged into one ordered Completeness dictionary.
        -Name reads only those values: the others are never built, so a phase does not pay for the
        large rows (sign-ins) it does not use. A row whose section is 'z-<Value>' holds one value
        too large to download in every phase (the raw mail records); it is fetched only when that
        value is named in -Name.
    .FUNCTIONALITY
        Internal
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$CaseId,
        [string[]]$Name
    )

    $Table = Get-CIPPTable -TableName 'BecRunState'
    $State = @{}
    $Completeness = [ordered]@{}
    $Fields = if ($Name) { [string[]]@(@($Name) + 'Completeness') } else { $null }
    $Rows = @("RowKey lt 'z'") + @(foreach ($Value in @($Name)) { if ($Value) { "RowKey eq 'z-$($Value -replace "'", "''")'" } })
    $Filter = "PartitionKey eq '$($CaseId -replace "'", "''")' and ($($Rows -join ' or '))"
    foreach ($Row in @(Get-CIPPAzDataTableEntity @Table -Filter $Filter | Where-Object { $_.Data } | Sort-Object -Property RowKey)) {
        $Values = [CIPP.CippJson]::ConvertFromJson([string]$Row.Data, $Fields)
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
