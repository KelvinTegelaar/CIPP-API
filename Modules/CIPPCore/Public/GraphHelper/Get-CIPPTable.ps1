function Get-CIPPTable {
    [CmdletBinding()]
    param (
        $tablename = 'CippLogs'
    )
    $Context = New-AzDataTableContext -ConnectionString $env:AzureWebJobsStorage -TableName $tablename
    New-AzDataTable -Context $Context | Out-Null

    @{
        Context = $Context
    }
}