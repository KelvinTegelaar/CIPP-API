function Write-AlertMessage($message, $tenant = 'None', $tenantId = $null) {
    <#
    .FUNCTIONALITY
    Internal
    #>
    $Table = Get-CIPPTable -tablename cachealerts
    $PartitionKey = (Get-Date -UFormat '%Y%m%d').ToString()
    $TableRow = @{
        'Tenant'       = [string]$tenant
        'Message'      = [string]$message
        'PartitionKey' = $PartitionKey
        'RowKey'       = ([guid]::NewGuid()).ToString()
    }
    $Table.Entity = $TableRow
    Add-CIPPAzDataTableEntity @Table | Out-Null
}