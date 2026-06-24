function Get-CIPPTable {
    <#
    .FUNCTIONALITY
    Internal
    #>
    [CmdletBinding()]
    param (
        $tablename = 'CippLogs'
    )
    $IsDevStorage = $env:AzureWebJobsStorage -eq 'UseDevelopmentStorage=true' -or $env:NonLocalHostAzurite -eq 'true'
    if (-not $IsDevStorage -and $env:IDENTITY_ENDPOINT) {
        # Prefer Managed Identity — avoids storing long-lived storage keys in environment
        $AccountName = ($env:AzureWebJobsStorage -split ';' | Where-Object { $_ -match '^AccountName=' }) -replace '^AccountName=', ''
        $ContextParams = @{
            ManagedIdentity = $true
            StorageAccountName = $AccountName
            TableName          = $tablename
        }
    } else {
        $ContextParams = @{
            ConnectionString = $env:AzureWebJobsStorage
            TableName        = $tablename
        }
    }
    $ContextParams['MaxConnectionsPerServer'] = if ($env:AZBOBBY_MAX_CONNECTIONS_PER_SERVER) { [int]$env:AZBOBBY_MAX_CONNECTIONS_PER_SERVER } else { 30 }
    $Context = New-AzDataTableContext @ContextParams
    New-AzDataTable -Context $Context | Out-Null

    @{
        Context = $Context
    }
}
