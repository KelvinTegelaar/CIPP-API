function Unregister-CIPPTable {
    <#
    .SYNOPSIS
    Forgets a table in the Get-CIPPTable "already created" cache so the next Get-CIPPTable for
    it creates it again. Call this after dropping a table with Remove-AzDataTable.

    .DESCRIPTION
    Without this the cache still claims a dropped table exists, so callers get empty results or
    TableNotFound. The cache is shared across the runspace pool, so one call covers every worker.

    .PARAMETER TableName
    Table(s) to forget. Names that were never cached are ignored.

    .PARAMETER All
    Forget every table, for callers that cannot know what was dropped.

    .EXAMPLE
    Remove-AzDataTable @TableContext
    Unregister-CIPPTable -TableName 'CippQueue'
    #>
    [CmdletBinding(DefaultParameterSetName = 'ByName')]
    param(
        [Parameter(ParameterSetName = 'ByName', Mandatory, ValueFromPipeline)]
        [string[]]$TableName,

        [Parameter(ParameterSetName = 'All', Mandatory)]
        [switch]$All
    )

    process {
        # Cold process, nothing to forget.
        if (-not $script:CIPPEnsuredTables) { return }

        if ($All) {
            $script:CIPPEnsuredTables.Clear()
            return
        }

        $Account = if ($env:AzureWebJobsStorage -match 'AccountName=([^;]+)') { $Matches[1] } else { 'default' }
        foreach ($Name in $TableName) {
            $script:CIPPEnsuredTables.Remove(('{0}/{1}' -f $Account, $Name))
        }
    }
}
