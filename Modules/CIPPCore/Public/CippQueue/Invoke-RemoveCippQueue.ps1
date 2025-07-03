function Invoke-RemoveCippQueue {
    <#
    .SYNOPSIS
    Remove all entries from the CIPP queue and task history
    
    .DESCRIPTION
    Clears all entries from the CIPP queue and associated task history tables for a full reset of queue data.
    
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        CIPP.Core.ReadWrite
        
    .NOTES
    Group: CIPP Queue
    Summary: Remove CIPP Queue
    Description: Clears all entries from the CIPP queue and associated task history tables for a full reset of queue data. This is typically used for maintenance or troubleshooting.
    Tags: Queue,Maintenance,Reset
    Response: Returns an object with the following properties:
    Response: - Results (array): Array with a single string indicating the history was cleared
    Response: On success: { "Results": ["History cleared"] } with HTTP 200 status
    Example: {
      "Results": ["History cleared"]
    }
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
