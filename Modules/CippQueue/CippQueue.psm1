using namespace System.Net

function New-CippQueueEntry {
    Param(
        $Name,
        $Link,
        $Reference
    )

    $CippQueue = Get-CippTable -TableName CippQueue

    $QueueEntry = @{
        PartitionKey = 'CippQueue'
        RowKey       = (New-Guid).Guid.ToString()
        Name         = $Name
        Link         = $Link
        Reference    = $Reference
        Status       = 'Queued'
    }
    $CippQueue.Entity = $QueueEntry

    Add-AzDataTableEntity @CippQueue

    $QueueEntry
}

function Update-CippQueueEntry {
    Param(
        [Parameter(Mandatory = $true)]
        $RowKey,
        $Status,
        $Name
    )

    $CippQueue = Get-CippTable -TableName CippQueue

    if ($RowKey) {
        $QueueEntry = Get-AzDataTableEntity @CippQueue -Filter ("RowKey eq '{0}'" -f $RowKey)

        if ($QueueEntry) {
            if ($Status) {
                $QueueEntry.Status = $Status
            }
            if ($Name) {
                $QueueEntry.Name = $Name
            }
            Update-AzDataTableEntity @CippQueue -Entity $QueueEntry
            $QueueEntry
        } else {
            return $false
        }
    } else {
        return $false
    }
}

function Get-CippQueue {
    # Input bindings are passed in via param block.
    param($Request = $null, $TriggerMetadata)

    if ($Request) {
        $APIName = $TriggerMetadata.FunctionName
        Write-LogMessage -user $request.headers.'x-ms-client-principal' -API $APINAME -message 'Accessed this API' -Sev 'Debug'

        # Write to the Azure Functions log stream.
        Write-Host 'PowerShell HTTP trigger function processed a request.'
    }

    $CippQueue = Get-CippTable -TableName 'CippQueue'
    $CippQueueData = Get-AzDataTableEntity @CippQueue | Where-Object { ($_.Timestamp.DateTime) -ge (Get-Date).ToUniversalTime().AddHours(-1) } | Sort-Object -Property Timestamp -Descending
    if ($request) {
        Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
                StatusCode = [HttpStatusCode]::OK
                Body       = @($CippQueueData)
            })
    } else {
        return $CippQueueData
    }
}

function Remove-CippQueue {
    # Input bindings are passed in via param block.
    param($Request, $TriggerMetadata)

    $APIName = $TriggerMetadata.FunctionName
    Write-LogMessage -user $request.headers.'x-ms-client-principal' -API $APINAME -message 'Accessed this API' -Sev 'Debug'

    # Write to the Azure Functions log stream.
    Write-Host 'PowerShell HTTP trigger function processed a request.'

    $CippQueue = Get-CippTable -TableName 'CippQueue'
    Clear-AzDataTable @CippQueue

    Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
            StatusCode = [HttpStatusCode]::OK
            Body       = @{Results = @('History cleared') }
        })
}


Export-ModuleMember -Function @('New-CippQueueEntry', 'Get-CippQueue', 'Update-CippQueueEntry', 'Remove-CippQueue')
