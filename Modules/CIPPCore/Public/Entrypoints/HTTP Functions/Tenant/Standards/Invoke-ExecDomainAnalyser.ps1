function Invoke-ExecDomainAnalyser {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        Tenant.DomainAnalyser.Read
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $ConfigTable = Get-CIPPTable -tablename Config
    $Config = Get-CIPPAzDataTableEntity @ConfigTable -Filter "PartitionKey eq 'OffloadFunctions' and RowKey eq 'OffloadFunctions'"

    if ($Config -and $Config.state -eq $true) {
        if ($env:CIPP_PROCESSOR -ne 'true') {
            $ProcessorFunction = [PSCustomObject]@{
                FunctionName      = 'CIPPFunctionProcessor'
                ProcessorFunction = 'Start-DomainOrchestrator'
            }
            Push-OutputBinding -Name QueueItem -Value $ProcessorFunction
        }
    } else {
        Start-DomainOrchestrator
    }

    Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
            StatusCode = [HttpStatusCode]::OK
            Body       = $results
        })
}
