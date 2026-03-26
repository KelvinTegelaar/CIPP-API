function Push-OrchestratorBatchItems {
    <#
    .FUNCTIONALITY
        Entrypoint
    #>
    [CmdletBinding()]
    param($Item)

    if ($Item.Parameters.BatchId) {
        $Table = Get-CippTable -TableName 'CippOrchestratorBatch'
        $Entities = Get-CIPPAzDataTableEntity @Table -Filter "PartitionKey eq '$($Item.Parameters.BatchId)'"
        $BatchItems = [system.Collections.Generic.List[object]]::new()
        $Entities | ForEach-Object {
            $Item = $_.BatchItem | ConvertFrom-Json
            $BatchItems.Add($Item)
        }
        Remove-AzDataTableEntity @Table -Entity $Entities -Force
        Write-Information "Retrieved $($BatchItems.Count) batch items for BatchId: $($Item.Parameters.BatchId)"
    } else {
        $BatchItems = [system.Collections.Generic.List[object]]::new()
    }
    return $BatchItems
}
