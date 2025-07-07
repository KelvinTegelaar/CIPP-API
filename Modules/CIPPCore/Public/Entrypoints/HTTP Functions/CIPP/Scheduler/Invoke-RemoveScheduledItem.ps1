using namespace System.Net

function Invoke-RemoveScheduledItem {
    <#
    .FUNCTIONALITY
        Entrypoint,AnyTenant
    .ROLE
        CIPP.Scheduler.ReadWrite
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $APIName = $Request.Params.CIPPEndpoint
    $Headers = $Request.Headers
    Write-LogMessage -headers $Headers -API $APIName -message 'Accessed this API' -Sev 'Debug'

    $RowKey = $Request.Query.id ? $Request.Query.id : $Request.Body.id
    $Task = @{
        RowKey       = $RowKey
        PartitionKey = 'ScheduledTask'
    }
    $Table = Get-CIPPTable -TableName 'ScheduledTasks'
    Remove-AzDataTableEntity -Force @Table -Entity $Task

    $DetailTable = Get-CIPPTable -TableName 'ScheduledTaskDetails'
    $Details = Get-CIPPAzDataTableEntity @DetailTable -Filter "PartitionKey eq '$($RowKey)'" -Property RowKey, PartitionKey, ETag

    if ($Details) {
        Remove-AzDataTableEntity -Force @DetailTable -Entity $Details
    }

    Write-LogMessage -Headers $Headers -API $APINAME -message "Task removed: $($Task.RowKey)" -Sev 'Info'

    return @{
        StatusCode = [HttpStatusCode]::OK
        Body       = @{ Results = 'Task removed successfully.' }
    }
}
