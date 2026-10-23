function Invoke-ListAlertRunHistory {
    <#
    .FUNCTIONALITY
        Entrypoint,AnyTenant
    .ROLE
        CIPP.Alert.Read
    .SYNOPSIS
        Lists scripted alert runs, newest first.
    .DESCRIPTION
        One row per scripted alert run per tenant: when it started, how long it took, its outcome (Completed,
        Skipped, Failed or Not reported) and how many alert items were new, reopened, continuing, resolved or
        snoozed. A run that found nothing still has a row, so this shows that an alert did run. Skipped rows
        are runs the scheduler held back because the alert ran within its minimum interval.
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $TenantFilter = $Request.Query.tenantFilter ?? $Request.Body.tenantFilter
    # Days of history to return, newest first (default 1, at most 30).
    $Days = ($Request.Query.Days ?? $Request.Body.Days) -as [int]
    # Only runs of this alert, by its scheduled task RowKey.
    $TaskId = $Request.Query.TaskId ?? $Request.Body.TaskId

    if ([string]::IsNullOrWhiteSpace($TenantFilter)) {
        return ([HttpResponseContext]@{
                StatusCode = [HttpStatusCode]::BadRequest
                Body       = @{ Results = 'tenantFilter is required.' }
            })
    }
    if (-not $Days -or $Days -lt 1) { $Days = 1 }
    if ($Days -gt 30) { $Days = 30 }

    try {
        $Table = Get-CIPPTable -tablename 'AlertRunHistory'
        $Conditions = @(
            if ($TaskId) { "TaskId eq '{0}'" -f (ConvertTo-CIPPODataFilterValue -Value $TaskId -Type String) }
            if ($TenantFilter -ne 'AllTenants') { "Tenant eq '{0}'" -f (ConvertTo-CIPPODataFilterValue -Value $TenantFilter -Type String) }
        )
        $Today = [datetime]::UtcNow.Date
        $Rows = foreach ($Offset in 0..($Days - 1)) {
            $Filter = (@("PartitionKey eq '$($Today.AddDays(-$Offset).ToString('yyyyMMdd'))'") + $Conditions) -join ' and '
            Get-CIPPAzDataTableEntity @Table -Filter $Filter
        }
        # AnyTenant skips the framework's tenant check, so restricted callers keep only rows for tenants in scope.
        $Results = foreach ($Row in @($Rows | Select-CippAllowedTenantData -TenantProperty 'Tenant')) {
            if ($null -eq $Row) { continue }
            [PSCustomObject]@{
                StartedUtc   = $Row.StartedUtc
                ScheduledUtc = $Row.ScheduledUtc
                TaskName     = $Row.TaskName
                Alert        = $Row.Alert
                Tenant       = $Row.Tenant
                Outcome      = $Row.Outcome
                Summary      = $Row.Summary
                New          = [int]$Row.New
                Reopened     = [int]$Row.Reopened
                Continuing   = [int]$Row.Continuing
                Resolved     = [int]$Row.Resolved
                Snoozed      = [int]$Row.Snoozed
                DurationMs   = [int64]$Row.DurationMs
                TaskId       = $Row.TaskId
            }
        }
        $StatusCode = [HttpStatusCode]::OK
    } catch {
        $Results = Get-NormalizedError -Message $_.Exception.Message
        $StatusCode = Get-CippErrorStatusCode -ErrorRecord $_
    }

    return ([HttpResponseContext]@{
            StatusCode = $StatusCode
            Body       = @($Results)
        })
}
