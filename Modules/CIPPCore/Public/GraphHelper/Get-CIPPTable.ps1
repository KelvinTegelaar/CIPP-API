function Get-CIPPTable {
    <#
    .FUNCTIONALITY
    Internal
    #>
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