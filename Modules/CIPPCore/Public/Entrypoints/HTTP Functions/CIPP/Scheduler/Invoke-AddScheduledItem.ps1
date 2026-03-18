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

    $HeaderProperties = @('x-ms-client-principal', 'x-ms-client-principal-id', 'x-ms-client-principal-name', 'x-forwarded-for')
    $Headers = $Request.Headers | Select-Object -Property $HeaderProperties -ErrorAction SilentlyContinue

    $Table = Get-CIPPTable -TableName 'ScheduledTasks'

    if ($Request.Body.RowKey) {
        $Filter = "PartitionKey eq 'ScheduledTask' and RowKey eq '$($Request.Body.RowKey)'"
        $ExistingTask = (Get-CIPPAzDataTableEntity @Table -Filter $Filter)
    }

    if ($ExistingTask -and $Request.Body.RunNow -eq $true) {
        $RerunParams = @{
            TenantFilter = $ExistingTask.Tenant
            Type         = 'ScheduledTask'
            API          = $Request.Body.RowKey
            Clear        = $true
        }
        $null = Test-CIPPRerun @RerunParams
        $Result = Add-CIPPScheduledTask -RowKey $Request.Body.RowKey -RunNow -Headers $Headers
    } else {
        $ScheduledTask = @{
            Task                  = $Request.Body
            Headers               = $Headers
            Hidden                = $hidden
            DisallowDuplicateName = $DisallowDuplicateName
            DesiredStartTime      = $Request.Body.DesiredStartTime
        }
        if ($Request.Body.RunNow -eq $true) {
            $ScheduledTask.RunNow = $true
        }
        $Result = Add-CIPPScheduledTask @ScheduledTask
    }
    return ([HttpResponseContext]@{
            StatusCode = [HttpStatusCode]::OK
            Body       = @{ Results = $Result }
        })
}
