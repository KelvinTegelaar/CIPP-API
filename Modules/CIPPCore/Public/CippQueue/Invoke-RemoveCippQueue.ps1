function Invoke-RemoveCippQueue {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        CIPP.Core.ReadWrite
    #>
    param($Request, $TriggerMetadata)
    $CippQueue = Get-CippTable -TableName 'CippQueue'
    Clear-AzDataTable @CippQueue
    $CippQueueTasks = Get-CippTable -TableName 'CippQueueTasks'
    Clear-AzDataTable @CippQueueTasks

    return ([HttpResponseContext]@{
            StatusCode = [HttpStatusCode]::OK
            Body       = @{Results = @('History cleared') }
        })
}
