function Write-AlertTrace {
    <#
    .FUNCTIONALITY
    Internal function. Pleases most of write-alertmessage for alerting purposes
    #>
    Param(
        $cmdletName,
        $data,
        $tenantFilter
    )   
    $Table = Get-CIPPTable -tablename AlertLastRun
    $PartitionKey = (Get-Date -UFormat '%Y%m%d').ToString()
    #Get current row and compare the $logData object. If it's the same, don't write it.
    $Row = Get-CIPPAzDataTableEntity @table -Filter "RowKey eq '$($tenantFilter)-$($cmdletName)' and PartitionKey eq '$PartitionKey'"
    try {
        $RowData = $Row.LogData
        $Compare = Compare-Object $RowData ($data | ConvertTo-Json -Compress -Depth 10 | Out-String)
        if ($Compare) {
            $LogData = ConvertTo-Json $data -Compress -Depth 10 | Out-String
            $TableRow = @{
                'PartitionKey' = $PartitionKey
                'RowKey'       = "$($tenantFilter)-$($cmdletName)"
                'LogData'      = [string]$LogData
            }
            $Table.Entity = $TableRow
            Add-CIPPAzDataTableEntity @Table -Force | Out-Null
            return $data
        }
    } catch {
        $LogData = ConvertTo-Json $data -Compress -Depth 10 | Out-String
        $TableRow = @{
            'PartitionKey' = $PartitionKey
            'RowKey'       = "$($tenantFilter)-$($cmdletName)"
            'LogData'      = [string]$LogData
        }
        $Table.Entity = $TableRow
        Add-CIPPAzDataTableEntity @Table -Force | Out-Null
        return $data
    }

}