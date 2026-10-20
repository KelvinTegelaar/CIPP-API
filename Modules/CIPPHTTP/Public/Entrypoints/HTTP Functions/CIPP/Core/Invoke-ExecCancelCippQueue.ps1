function Invoke-ExecCancelCippQueue {
    <#
    .FUNCTIONALITY
        Entrypoint,AnyTenant
    .ROLE
        CIPP.Core.Read
    .DESCRIPTION
        Cancels the waiting tasks of a background queue the caller started, such as an All Tenants table load. Tasks already running finish. Only the user who started a queue can cancel it.
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $APIName = $Request.Params.CIPPEndpoint
    $Headers = $Request.Headers
    # The QueueId a queued list response returned in Metadata.QueueId
    $QueueId = [string]$Request.Body.QueueId
    $User = [string]$Headers.'x-ms-client-principal-name'

    if (-not $QueueId) {
        return ([HttpResponseContext]@{ StatusCode = [HttpStatusCode]::BadRequest; Body = @{ Results = 'QueueId is required' } })
    }
    if ($env:CIPPNG -ne 'true') {
        return ([HttpResponseContext]@{ StatusCode = [HttpStatusCode]::BadRequest; Body = @{ Results = 'This instance does not support cancelling queues.' } })
    }

    try {
        $CippQueue = Get-CippTable -TableName CippQueue
        $SafeQueueId = ConvertTo-CIPPODataFilterValue -Value $QueueId -Type String
        $Entry = Get-CIPPAzDataTableEntity @CippQueue -Filter "PartitionKey eq 'CippQueue' and RowKey eq '$SafeQueueId'" -Property PartitionKey, RowKey, Owner, Name
        if (-not $Entry) {
            return ([HttpResponseContext]@{ StatusCode = [HttpStatusCode]::NotFound; Body = @{ Results = 'Queue not found.' } })
        }
        if (-not $User -or $Entry.Owner -ne $User) {
            return ([HttpResponseContext]@{ StatusCode = [HttpStatusCode]::Forbidden; Body = @{ Results = 'You can only cancel queues you started.' } })
        }

        $Runs = [Craft.Services.QueueStatusBridge]::GetRuns($QueueId) | ConvertFrom-Json
        $Cancelled = [int](@(foreach ($Run in $Runs) { [Craft.Services.WorkerMetricsBridge]::CancelRun($Run.runName) }) | Measure-Object -Sum).Sum
        Write-LogMessage -headers $Headers -API $APIName -message "Cancelled queue '$($Entry.Name)': $Cancelled waiting task(s)" -Sev 'Info'
        $Result = "Cancelled $Cancelled waiting task(s). Tasks already running will finish."
        $StatusCode = [HttpStatusCode]::OK
    } catch {
        $Result = "Failed to cancel queue: $($_.Exception.Message)"
        Write-LogMessage -headers $Headers -API $APIName -message $Result -Sev 'Error'
        $StatusCode = Get-CippErrorStatusCode -ErrorRecord $_
    }

    return ([HttpResponseContext]@{
            StatusCode = $StatusCode
            Body       = @{ Results = $Result }
        })
}
