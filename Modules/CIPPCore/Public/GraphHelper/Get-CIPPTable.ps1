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

    # New-AzDataTable 409s once the table exists, and those 409s bill like any other request.
    # This runs on nearly every code path, so skip the round trip for tables we know exist.
    # Anything that drops a table must call Unregister-CIPPTable.
    #
    # Craft injects the cache (ModuleInjections/CIPPTableCache) so all runspaces share one
    # instance. Mutate it, never reassign, or this runspace gets a private copy.
    if (-not $script:CIPPEnsuredTables) { $script:CIPPEnsuredTables = [HashTable]::Synchronized(@{}) }

    # Account is in the key: AzureWebJobsStorage can be repointed at a different account.
    $Account = if ($env:AzureWebJobsStorage -match 'AccountName=([^;]+)') { $Matches[1] } else { 'default' }
    $CacheKey = '{0}/{1}' -f $Account, $tablename

    if (-not $script:CIPPEnsuredTables.ContainsKey($CacheKey)) {
        New-AzDataTable -Context $Context | Out-Null
        $script:CIPPEnsuredTables[$CacheKey] = $true
    }

    @{
        Context = $Context
    }
}
