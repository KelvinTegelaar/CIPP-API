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
                PartitionKey = 'Function'
                RowKey       = 'Start-ApplicationOrchestrator'
                FunctionName = 'Start-ApplicationOrchestrator'
            }
            $ProcessorQueue = Get-CIPPTable -TableName 'ProcessorQueue'
            Add-AzDataTableEntity @ProcessorQueue -Entity $ProcessorFunction -Force
            $Results = [pscustomobject]@{'Results' = 'Application upload job has started. Please check back in 15 minutes or track the logbook for results.' }
        }
    } else {
        try {
            Start-ApplicationOrchestrator
            $Results = [pscustomobject]@{'Results' = 'Started application upload' }
        } catch {
            $Results = [pscustomobject]@{'Results' = "Failed to start application upload. Error: $($_.Exception.Message)" }
        }
    }

    Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
            StatusCode = [HttpStatusCode]::OK
            Body       = $Results
        })

}
