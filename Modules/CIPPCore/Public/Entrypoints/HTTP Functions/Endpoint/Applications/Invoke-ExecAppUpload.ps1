function Invoke-ExecAppUpload {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        Endpoint.Application.ReadWrite
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $ConfigTable = Get-CIPPTable -tablename Config
    $Config = Get-CIPPAzDataTableEntity @ConfigTable -Filter "PartitionKey eq 'OffloadFunctions' and RowKey eq 'OffloadFunctions'"

    if ($Config -and $Config.state -eq $true) {
        if ($env:CIPP_PROCESSOR -ne 'true') {
            $ProcessorFunction = [PSCustomObject]@{
                FunctionName      = 'CIPPFunctionProcessor'
                ProcessorFunction = 'Start-ApplicationOrchestrator'
            }
            Push-OutputBinding -Name QueueItem -Value $ProcessorFunction
        }
    } else {
        try {
            Start-ApplicationOrchestrator
        } catch {
            Write-Host "orchestrator error: $($_.Exception.Message)"
        }
    }

    $Results = [pscustomobject]@{'Results' = 'Started application queue' }
    Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
            StatusCode = [HttpStatusCode]::OK
            Body       = $results
        })

}
