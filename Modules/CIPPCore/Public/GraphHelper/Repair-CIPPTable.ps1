function Repair-CIPPTable {
    <#
    .SYNOPSIS
    Recreates a missing Azure table and refreshes the Get-CIPPTable ensure-cache.

    .DESCRIPTION
    Used when entity operations fail with TableNotFound because CIPPEnsuredTables still claims
    the table exists (migration, external delete, or a drop without Unregister-CIPPTable).
    Invalidates the cache entry, issues CreateTable, then marks the table ensured again.
    Concurrent creates that 409 are treated as success.

    Do not call Write-LogMessage from here - logging reads tables and would re-enter the wrappers.

    .PARAMETER Context
    AzBobbyTables context for the missing table (must include TableName).

    .PARAMETER TableName
    Table to recreate when a context is not already available.
    #>
    [CmdletBinding(DefaultParameterSetName = 'ByContext')]
    param(
        [Parameter(ParameterSetName = 'ByContext', Mandatory)]
        $Context,

        [Parameter(ParameterSetName = 'ByName', Mandatory)]
        [string]$TableName
    )

    if ($PSCmdlet.ParameterSetName -eq 'ByContext') {
        if ($null -eq $Context) {
            throw 'Context parameter cannot be null'
        }
        $TableName = [string]$Context.TableName
        if ([string]::IsNullOrWhiteSpace($TableName)) {
            throw 'Context.TableName is required'
        }
        $TableContext = $Context
    } else {
        $ContextParams = @{
            ConnectionString = $env:AzureWebJobsStorage
            TableName        = $TableName
        }
        $ContextParams['MaxConnectionsPerServer'] = if ($env:AZBOBBY_MAX_CONNECTIONS_PER_SERVER) { [int]$env:AZBOBBY_MAX_CONNECTIONS_PER_SERVER } else { 30 }
        $TableContext = New-AzDataTableContext @ContextParams
    }

    Unregister-CIPPTable -TableName $TableName

    # Same cache contract as Get-CIPPTable: mutate the shared hashtable, never reassign.
    if (-not $script:CIPPEnsuredTables) { $script:CIPPEnsuredTables = [HashTable]::Synchronized(@{}) }
    $Account = if ($env:AzureWebJobsStorage -match 'AccountName=([^;]+)') { $Matches[1] } else { 'default' }
    $CacheKey = '{0}/{1}' -f $Account, $TableName

    try {
        New-AzDataTable -Context $TableContext | Out-Null
    } catch {
        # Another worker may have created it between unregister and create.
        if (-not (Test-CIPPTableAlreadyExists $_)) {
            throw
        }
    }

    $script:CIPPEnsuredTables[$CacheKey] = $true
    Write-Information "[Tables-Repair] Recreated missing table $TableName on $Account"
}

function Test-CIPPTableAlreadyExists {
    <#
    .SYNOPSIS
    Returns true when CreateTable failed because the table already exists (HTTP 409).
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory, Position = 0)]
        $ErrorRecord
    )

    $Messages = [System.Collections.Generic.List[string]]::new()
    $Exceptions = [System.Collections.Generic.List[System.Exception]]::new()

    if ($ErrorRecord -is [System.Management.Automation.ErrorRecord]) {
        $Messages.Add([string]$ErrorRecord.FullyQualifiedErrorId)
        if ($ErrorRecord.Exception) { $Exceptions.Add($ErrorRecord.Exception) }
    } elseif ($ErrorRecord -is [System.Exception]) {
        $Exceptions.Add($ErrorRecord)
    } else {
        $Messages.Add([string]$ErrorRecord)
    }

    foreach ($Exception in $Exceptions) {
        $Current = $Exception
        while ($Current) {
            $Messages.Add([string]$Current.Message)
            foreach ($PropName in @('ErrorCode', 'Code')) {
                $Prop = $Current.PSObject.Properties[$PropName]
                if ($Prop -and $Prop.Value) { $Messages.Add([string]$Prop.Value) }
            }
            foreach ($PropName in @('Status', 'StatusCode', 'HttpStatusCode')) {
                $Prop = $Current.PSObject.Properties[$PropName]
                if ($Prop -and $null -ne $Prop.Value) {
                    $Status = $Prop.Value
                    if ($Status -is [enum]) { $Status = [int]$Status }
                    if ([string]$Status -eq '409' -or [int]$Status -eq 409) {
                        return $true
                    }
                }
            }
            $Current = $Current.InnerException
        }
    }

    foreach ($Message in $Messages) {
        if ([string]::IsNullOrWhiteSpace($Message)) { continue }
        if ($Message -match '(?i)TableAlreadyExists|already exists|Conflict|\b409\b') {
            return $true
        }
    }

    $false
}
