function Invoke-AddScheduledItem {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        CIPP.Scheduler.ReadWrite
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)
    if ($null -eq $Request.Query.hidden) {
        $hidden = $false
    } else {
        $hidden = $true
    }

    $DisallowDuplicateName = $Request.Query.DisallowDuplicateName ?? $Request.Body.DisallowDuplicateName

    if ($Request.Body.RunNow -eq $true) {
        try {
            $Table = Get-CIPPTable -TableName 'ScheduledTasks'
            $Filter = "PartitionKey eq 'ScheduledTask' and RowKey eq '$($Request.Body.RowKey)'"
            $ExistingTask = (Get-CIPPAzDataTableEntity @Table -Filter $Filter)
            if ($ExistingTask) {
                $Result = Add-CIPPScheduledTask -RowKey $Request.Body.RowKey -RunNow -Headers $Request.Headers
            } else {
                $Result = "Task with id $($Request.Body.RowKey) does not exist"
            }
        } catch {
            Write-Warning "Error scheduling task: $($_.Exception.Message)"
            Write-Information $_.InvocationInfo.PositionMessage
            $Result = "Error scheduling task: $($_.Exception.Message)"
        }
    } else {
        $ScheduledTask = @{
            Task                  = $Request.Body
            Headers               = $Request.Headers
            Hidden                = $hidden
            DisallowDuplicateName = $DisallowDuplicateName
            DesiredStartTime      = $Request.Body.DesiredStartTime
        }
        $Result = Add-CIPPScheduledTask @ScheduledTask
    }
    return ([HttpResponseContext]@{
            StatusCode = [HttpStatusCode]::OK
            Body       = @{ Results = $Result }
        })
}
