using namespace System.Net

function Invoke-AddScheduledItem {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        CIPP.Scheduler.ReadWrite
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $APIName = $Request.Params.CIPPEndpoint
    $Headers = $Request.Headers
    Write-LogMessage -headers $Headers -API $APIName -message 'Accessed this API' -Sev 'Debug'

    if ($null -eq $Request.Query.hidden) {
        $hidden = $false
    } else {
        $hidden = $true
    }

    if ($Request.Body.RunNow -eq $true) {
        try {
            $Table = Get-CIPPTable -TableName 'ScheduledTasks'
            $Filter = "PartitionKey eq 'ScheduledTask' and RowKey eq '$($Request.Body.RowKey)'"
            $ExistingTask = (Get-CIPPAzDataTableEntity @Table -Filter $Filter)
            if ($ExistingTask) {
                $Result = Add-CIPPScheduledTask -RowKey $Request.Body.RowKey -RunNow -Headers $Headers
            } else {
                $Result = "Task with id $($Request.Body.RowKey) does not exist"
            }
        } catch {
            Write-Warning "Error scheduling task: $($_.Exception.Message)"
            Write-Information $_.InvocationInfo.PositionMessage
            $Result = "Error scheduling task: $($_.Exception.Message)"
        }
    } else {
        $Result = Add-CIPPScheduledTask -Task $Request.Body -Headers $Headers -hidden $hidden -DisallowDuplicateName $Request.Query.DisallowDuplicateName
        Write-LogMessage -headers $Headers -API $APINAME -message $Result -Sev 'Info'
    }
    return @{
        StatusCode = [HttpStatusCode]::OK
        Body       = @{ Results = $Result }
    }
}
