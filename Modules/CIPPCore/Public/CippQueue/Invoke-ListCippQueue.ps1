function Invoke-ListCippQueue {
    <#
    .SYNOPSIS
    List CIPP queue entries and their task status
    
    .DESCRIPTION
    Retrieves a list of CIPP queue entries with detailed task status, progress information, and completion statistics
    
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        CIPP.Core.Read
        
    .NOTES
    Group: CIPP Queue
    Summary: List CIPP Queue
    Description: Retrieves a list of CIPP queue entries from the last 3 hours with detailed task status, progress tracking, and completion statistics
    Tags: Queue,Monitoring,Progress
    Response: Returns an array of queue objects with the following properties:
    Response: - PartitionKey (string): Queue partition key
    Response: - RowKey (string): Queue unique identifier
    Response: - Name (string): Queue name or description
    Response: - Link (string): Reference link for the queue
    Response: - Reference (string): Additional reference information
    Response: - TotalTasks (number): Total number of tasks in the queue
    Response: - CompletedTasks (number): Number of completed tasks (including failed)
    Response: - RunningTasks (number): Number of currently running tasks
    Response: - FailedTasks (number): Number of failed tasks
    Response: - PercentComplete (number): Percentage of tasks completed
    Response: - PercentFailed (number): Percentage of tasks that failed
    Response: - PercentRunning (number): Percentage of tasks currently running
    Response: - Tasks (array): Array of individual task objects with timestamp, name, and status
    Response: - Status (string): Overall queue status: Running, Completed, or Completed (with errors)
    Response: - Timestamp (string): Queue creation timestamp
    Example: [
      {
        "PartitionKey": "CippQueue",
        "RowKey": "12345678-1234-1234-1234-123456789012",
        "Name": "Tenant License Update",
        "Link": "https://example.com/reference",
        "Reference": "License audit 2024",
        "TotalTasks": 10,
        "CompletedTasks": 8,
        "RunningTasks": 1,
        "FailedTasks": 1,
        "PercentComplete": 80.0,
        "PercentFailed": 10.0,
        "PercentRunning": 10.0,
        "Tasks": [
          {
            "Timestamp": "2024-01-15T10:30:00Z",
            "Name": "Update tenant A",
            "Status": "Completed"
          }
        ],
        "Status": "Running",
        "Timestamp": "2024-01-15T10:00:00Z"
      }
    ]
    #>
    [CmdletBinding()]
    param($Request = $null, $TriggerMetadata = $null)

    if ($Request) {
        $APIName = $Request.Params.CIPPEndpoint
        Write-LogMessage -headers $Request.Headers -API $APINAME -message 'Accessed this API' -Sev 'Debug'
    }

    $CippQueue = Get-CippTable -TableName 'CippQueue'
    $CippQueueTasks = Get-CippTable -TableName 'CippQueueTasks'
    $3HoursAgo = (Get-Date).ToUniversalTime().AddHours(-3).ToString('yyyy-MM-ddTHH:mm:ssZ')
    $CippQueueData = Get-CIPPAzDataTableEntity @CippQueue -Filter "Timestamp ge datetime'$3HoursAgo'" | Sort-Object -Property Timestamp -Descending

    $QueueData = foreach ($Queue in $CippQueueData) {
        $Tasks = Get-CIPPAzDataTableEntity @CippQueueTasks -Filter "QueueId eq '$($Queue.RowKey)'" | Where-Object { $_.Name } | Select-Object @{n = 'Timestamp'; exp = { $_.Timestamp.DateTime.ToUniversalTime() } }, Name, Status
        $TaskStatus = @{}
        $Tasks | Group-Object -Property Status | ForEach-Object {
            $TaskStatus.$($_.Name) = $_.Count
        }

        if ($Tasks) {
            if ($Tasks.Status -notcontains 'Running' -and ($TaskStatus.Completed + $TaskStatus.Failed) -ge $Queue.TotalTasks) {
                if ($Tasks.Status -notcontains 'Failed') {
                    $Queue.Status = 'Completed'
                }
                else {
                    $Queue.Status = 'Completed (with errors)'
                }
            }
            else {
                $Queue.Status = 'Running'
            }
        }

        $TotalCompleted = $TaskStatus.Completed ?? 0
        $TotalFailed = $TaskStatus.Failed ?? 0
        $TotalRunning = $TaskStatus.Running ?? 0
        if ($Queue.TotalTasks -eq 0) { $Queue.TotalTasks = 1 }

        [PSCustomObject]@{
            PartitionKey    = $Queue.PartitionKey
            RowKey          = $Queue.RowKey
            Name            = $Queue.Name
            Link            = $Queue.Link
            Reference       = $Queue.Reference
            TotalTasks      = $Queue.TotalTasks
            CompletedTasks  = $TotalCompleted + $TotalFailed
            RunningTasks    = $TotalRunning
            FailedTasks     = $TotalFailed
            PercentComplete = [math]::Round(((($TotalCompleted + $TotalFailed) / $Queue.TotalTasks) * 100), 1)
            PercentFailed   = [math]::Round((($TotalFailed / $Queue.TotalTasks) * 100), 1)
            PercentRunning  = [math]::Round((($TotalRunning / $Queue.TotalTasks) * 100), 1)
            Tasks           = @($Tasks)
            Status          = $Queue.Status
            Timestamp       = $Queue.Timestamp.DateTime.ToUniversalTime()
        }

    }

    if ($request) {
        Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
                StatusCode = [HttpStatusCode]::OK
                Body       = @($QueueData)
            })
    }
    else {
        return $QueueData
    }
}
