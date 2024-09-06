function Invoke-ExecBPA {
    <#
        .FUNCTIONALITY
        Entrypoint
        .ROLE
        Tenant.BestPracticeAnalyser.ReadWrite
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)


    $ConfigTable = Get-CIPPTable -tablename Config
    $Config = Get-CIPPAzDataTableEntity @ConfigTable -Filter "PartitionKey eq 'OffloadFunctions' and RowKey eq 'OffloadFunctions'"

    if ($Config -and $Config.state -eq $true) {
        if ($env:CIPP_PROCESSOR -ne 'true') {
            $ProcessorFunction = [PSCustomObject]@{
                FunctionName      = 'CIPPFunctionProcessor'
                ProcessorFunction = 'Start-BPAOrchestrator'
                Parameters        = [PSCustomObject]@{
                    TenantFilter = $Request.Query.TenantFilter
                }
            }
            Push-OutputBinding -Name QueueItem -Value $ProcessorFunction
        }
    } else {
        Start-BPAOrchestrator -TenantFilter $Request.Query.TenantFilter
    }
    $Results = [pscustomobject]@{'Results' = 'BPA started' }
    Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
            StatusCode = [HttpStatusCode]::OK
            Body       = $Results
        })

}
