function Clear-CIPPQueueData {
    param($Request = $null, $TriggerMetadata = $null)
    $CippQueue = Get-CippTable -TableName 'CippQueue'
    Clear-AzDataTable @CippQueue
    $CippQueueTasks = Get-CippTable -TableName 'CippQueueTasks'
    Clear-AzDataTable @CippQueueTasks

    return @{Results = @('History cleared') }
}
