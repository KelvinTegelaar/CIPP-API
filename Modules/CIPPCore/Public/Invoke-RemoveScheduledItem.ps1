using namespace System.Net

Function Invoke-RemoveScheduledItem {
    <#
    .FUNCTIONALITY
    Entrypoint
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $task = @{
        RowKey       = $Request.Query.ID
        PartitionKey = 'ScheduledTask'
    }
    $Table = Get-CIPPTable -TableName 'ScheduledTasks'
    Remove-AzDataTableEntity @Table -Entity $task
    Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
            StatusCode = [HttpStatusCode]::OK
            Body       = @{ Results = 'Task removed successfully.' } 
        })
    $Table = Get-CIPPTable -TableName 'ScheduledTasks'
    Remove-AzDataTableEntity @Table -Entity $task
    Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
            StatusCode = [HttpStatusCode]::OK
            Body       = @{ Results = 'Task removed successfully.' } 
        })

}
