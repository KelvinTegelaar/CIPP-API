function Get-CIPPTable {
    <#
    .FUNCTIONALITY
    Internal
    #>
    [CmdletBinding()]
    param (
        $tablename = 'CippLogs'
    )
    $ContextParams = @{
        ConnectionString = $env:AzureWebJobsStorage
        TableName        = $tablename
    }
    $ContextParams['MaxConnectionsPerServer'] = if ($env:AZBOBBY_MAX_CONNECTIONS_PER_SERVER) { [int]$env:AZBOBBY_MAX_CONNECTIONS_PER_SERVER } else { 30 }
    $Context = New-AzDataTableContext @ContextParams
    New-AzDataTable -Context $Context | Out-Null

    @{
        Context = $Context
    }
}
