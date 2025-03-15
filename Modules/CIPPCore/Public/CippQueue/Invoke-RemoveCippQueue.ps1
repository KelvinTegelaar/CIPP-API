function Invoke-RemoveCippQueue {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        CIPP.Core.ReadWrite
    #>
    param($Request, $TriggerMetadata)

    $APIName = $Request.Params.CIPPEndpoint
    $Headers = $Request.Headers
    Write-LogMessage -headers $Headers -API $APIName -message 'Accessed this API' -Sev 'Debug'

    $CippQueue = Get-CippTable -TableName 'CippQueue'
    Clear-AzDataTable @CippQueue
    $CippQueueTasks = Get-CippTable -TableName 'CippQueueTasks'
    Clear-AzDataTable @CippQueueTasks

    Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
            StatusCode = [HttpStatusCode]::OK
            Body       = @{Results = @('History cleared') }
        })
}
