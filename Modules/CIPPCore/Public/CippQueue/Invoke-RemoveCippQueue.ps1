function Invoke-RemoveCippQueue {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        CIPP.Core.ReadWrite
    #>
    param($Request, $TriggerMetadata)

    $APIName = $Request.Params.CIPPEndpoint
    Write-LogMessage -headers $Request.Headers -API $APINAME -message 'Accessed this API' -Sev 'Debug'

    # Write to the Azure Functions log stream.
    Write-Host 'PowerShell HTTP trigger function processed a request.'

    $CippQueue = Get-CippTable -TableName 'CippQueue'
    Clear-AzDataTable @CippQueue
    $CippQueueTasks = Get-CippTable -TableName 'CippQueueTasks'
    Clear-AzDataTable @CippQueueTasks

    Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
            StatusCode = [HttpStatusCode]::OK
            Body       = @{Results = @('History cleared') }
        })
}
