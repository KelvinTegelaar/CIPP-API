function Initialize-CIPPTables {
    <#
    .SYNOPSIS
    Seeds the Get-CIPPTable "this table already exists" cache at warmup, from a single
    ListTables call against the storage account.

    .DESCRIPTION
    Get-CIPPTable already caps CreateTable at one call per table; this removes even those, so a
    warm instance issues none at all.

    A listing rather than a fixed list: a hardcoded list rots as features add tables, and many
    table names are derived from Graph queries at runtime so a list could never cover them.

    Best effort - if the listing fails, Get-CIPPTable just creates each table on first use.
    Tables that do not exist yet are deliberately left out so first use still creates them.
    #>
    [CmdletBinding()]
    param()

    if (-not $env:AzureWebJobsStorage) {
        Write-Warning '[Tables-Init] AzureWebJobsStorage is not set, skipping table cache warmup'
        return
    }

    $Account = if ($env:AzureWebJobsStorage -match 'AccountName=([^;]+)') { $Matches[1] } else { 'default' }

    try {
        $ContextParams = @{
            ConnectionString = $env:AzureWebJobsStorage
            TableName        = 'CippLogs'
        }
        $ContextParams['MaxConnectionsPerServer'] = if ($env:AZBOBBY_MAX_CONNECTIONS_PER_SERVER) { [int]$env:AZBOBBY_MAX_CONNECTIONS_PER_SERVER } else { 30 }
        $Context = New-AzDataTableContext @ContextParams

        # Account-scoped listing; the context's TableName is unused, which the cmdlet warns about.
        $Existing = @(Get-AzDataTable -Context $Context -WarningAction SilentlyContinue)
    } catch {
        # Storage may not be up yet at warmup. Not fatal.
        Write-Warning "[Tables-Init] Could not list tables on $Account, they will be created on first use: $($_.Exception.Message)"
        return
    }

    if (-not $Existing.Count) {
        Write-Information "[Tables-Init] No existing tables on $Account (new instance) - they will be created on first use"
        return
    }

    # Shared across runspaces - mutate, never reassign. See Get-CIPPTable.
    if (-not $script:CIPPEnsuredTables) { $script:CIPPEnsuredTables = [HashTable]::Synchronized(@{}) }
    foreach ($TableName in $Existing) {
        $script:CIPPEnsuredTables[('{0}/{1}' -f $Account, $TableName)] = $true
    }

    Write-Information "[Tables-Init] Cached $($Existing.Count) existing table(s) on $Account - CreateTable will be skipped for them"
}
