function Write-AlertTrace {
    <#
    .FUNCTIONALITY
    Internal function. Pleases most of Write-AlertTrace for alerting purposes
    #>
    param(
        $cmdletName,
        $data,
        $tenantFilter,
        [string]$PartitionKey = (Get-Date -UFormat '%Y%m%d').ToString(),
        [string]$AlertComment = $null
    )
    $Table = Get-CIPPTable -tablename AlertLastRun
    #Get current row and compare the $logData object. If it's the same, don't write it.
    $Row = Get-CIPPAzDataTableEntity @table -Filter "RowKey eq '$($tenantFilter)-$($cmdletName)' and PartitionKey eq '$PartitionKey'"
    try {
        $RowData = $Row.LogData
        $Compare = Compare-Object $RowData (ConvertTo-Json -InputObject $data -Compress -Depth 10 | Out-String)
        if ($Compare) {
            $LogData = ConvertTo-Json -InputObject $data -Compress -Depth 10 | Out-String
            $TableRow = @{
                'PartitionKey' = $PartitionKey
                'RowKey'       = "$($tenantFilter)-$($cmdletName)"
                'CmdletName'   = "$cmdletName"
                'Tenant'       = "$tenantFilter"
                'LogData'      = [string]$LogData
                'AlertComment' = [string]$AlertComment
            }
            $Table.Entity = $TableRow
            Add-CIPPAzDataTableEntity @Table -Force | Out-Null
            return $data
        }
    } catch {
        $LogData = ConvertTo-Json -InputObject $data -Compress -Depth 10 | Out-String
        $TableRow = @{
            'PartitionKey' = $PartitionKey
            'RowKey'       = "$($tenantFilter)-$($cmdletName)"
            'CmdletName'   = "$cmdletName"
            'Tenant'       = "$tenantFilter"
            'LogData'      = [string]$LogData
            'AlertComment' = [string]$AlertComment
        }
        $Table.Entity = $TableRow
        Add-CIPPAzDataTableEntity @Table -Force | Out-Null
        return $data
    }

}
