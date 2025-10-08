function Invoke-ExecDomainAnalyser {
    <#
    .FUNCTIONALITY
        Entrypoint,AnyTenant
    .ROLE
        Tenant.DomainAnalyser.ReadWrite
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $ConfigTable = Get-CIPPTable -tablename Config
    $Config = Get-CIPPAzDataTableEntity @ConfigTable -Filter "PartitionKey eq 'OffloadFunctions' and RowKey eq 'OffloadFunctions'"

    if ($Config -and $Config.state -eq $true) {
        if ($env:CIPP_PROCESSOR -ne 'true') {
            $ProcessorFunction = [PSCustomObject]@{
                PartitionKey = 'Function'
                RowKey       = 'Start-DomainOrchestrator'
                FunctionName = 'Start-DomainOrchestrator'
            }
            $ProcessorQueue = Get-CIPPTable -TableName 'ProcessorQueue'
            Add-AzDataTableEntity @ProcessorQueue -Entity $ProcessorFunction -Force
            $Results = [pscustomobject]@{'Results' = 'Queueing Domain Analyser' }
        }
    } else {
        $OrchStatus = Start-DomainOrchestrator
        if ($OrchStatus) {
            $Message = 'Domain Analyser started'
        } else {
            $Message = 'Domain Analyser error: check logs'
        }
        $Results = [pscustomobject]@{'Results' = $Message }
    }

    return ([HttpResponseContext]@{
            StatusCode = [HttpStatusCode]::OK
            Body       = $Results
        })
}
