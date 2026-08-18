function Invoke-RemoveScheduledItem {
    <#
    .FUNCTIONALITY
        Entrypoint,AnyTenant
    .ROLE
        CIPP.Scheduler.ReadWrite
    .DESCRIPTION
        Removes a scheduled item from CIPP's scheduler.
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $APIName = $Request.Params.CIPPEndpoint
    $Headers = $Request.Headers

    $RowKey = $Request.Query.id ? $Request.Query.id : $Request.Body.id
    $task = @{
        RowKey       = $RowKey
        PartitionKey = 'ScheduledTask'
    }
    try {
        $Table = Get-CIPPTable -TableName 'ScheduledTasks'

        # AnyTenant: restricted callers may only remove tasks for tenants in scope
        $AllowedTenants = Test-CIPPAccess -Request $Request -TenantList
        if ($AllowedTenants -notcontains 'AllTenants') {
            $SafeRowKey = ConvertTo-CIPPODataFilterValue -Value $RowKey -Type String
            $Existing = Get-CIPPAzDataTableEntity @Table -Filter "PartitionKey eq 'ScheduledTask' and RowKey eq '$SafeRowKey'"
            if (-not $Existing.Tenant -or -not (Get-Tenants -TenantFilter $Existing.Tenant)) {
                return ([HttpResponseContext]@{
                        StatusCode = [HttpStatusCode]::Forbidden
                        Body       = @{ Results = 'Access to this scheduled task is not allowed' }
                    })
            }
        }

        Remove-CIPPAzDataTableEntity -Force @Table -Entity $task

        $DetailTable = Get-CIPPTable -TableName 'ScheduledTaskDetails'
        $Details = Get-CIPPAzDataTableEntity @DetailTable -Filter "PartitionKey eq '$($RowKey)'" -Property RowKey, PartitionKey, ETag

        if ($Details) {
            Remove-CIPPAzDataTableEntity -Force @DetailTable -Entity $Details
        }

        Write-LogMessage -Headers $Headers -API $APIName -message "Task removed: $($task.RowKey)" -Sev 'Info'
        $StatusCode = [HttpStatusCode]::OK
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Write-LogMessage -Headers $Headers -API $APIName -message "Failed to remove task: $($task.RowKey). $($ErrorMessage.NormalizedError)" -Sev 'Error' -LogData $ErrorMessage
        $StatusCode = [HttpStatusCode]::BadRequest
    }

    return ([HttpResponseContext]@{
            StatusCode = $StatusCode
            Body       = @{ Results = 'Task removed successfully.' }
        })

}
