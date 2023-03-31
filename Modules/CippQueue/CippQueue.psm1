using namespace System.Net

function New-CippQueueEntry {
    Param(
        $Name,
        $Link
    )

    $CippQueue = Get-CippTable -TableName CippQueue

    $QueueEntry = @{
        PartitionKey = 'CippQueue'
        RowKey       = (New-Guid).Guid.ToString()
        Name         = $Name
        Link         = $Link
        Status       = 'Queued'
    }
    $CippQueue.Entity = $QueueEntry

    Add-AzDataTableEntity @CippQueue

    $QueueEntry
}

function Update-CippQueueEntry {
    Param(
        $RowKey,
        $Status
    )

    $CippQueue = Get-CippTable -TableName CippQueue

    if ($RowKey) {
        $QueueEntry = Get-AzDataTableEntity @CippQueue -Filter ("RowKey eq '{0}'" -f $RowKey)

        if ($QueueEntry) {
            $QueueEntry.Status = $Status
            Update-AzDataTableEntity @CippQueue -Entity $QueueEntry

            $QueueEntry
        }
        else {
            return $false
        }
    }
    else {
        return $false
    }
}

function Get-CippQueue {
    # Input bindings are passed in via param block.
    param($Request, $TriggerMetadata)

    $APIName = $TriggerMetadata.FunctionName
    Write-LogMessage -user $request.headers.'x-ms-client-principal' -API $APINAME -message 'Accessed this API' -Sev 'Debug'

    # Write to the Azure Functions log stream.
    Write-Host 'PowerShell HTTP trigger function processed a request.'

    $CippQueue = Get-CippTable -TableName 'CippQueue'
    $CippQueueData = Get-AzDataTableEntity @CippQueue 

    Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
            StatusCode = [HttpStatusCode]::OK
            Body       = @($CippQueueData)
        })
}

Export-ModuleMember -Function @('New-CippQueueEntry', 'Get-CippQueue', 'Update-CippQueueEntry')
