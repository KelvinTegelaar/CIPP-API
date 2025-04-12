using namespace System.Net

function Invoke-ListScheduledItemDetails {
    <#
    .FUNCTIONALITY
        Entrypoint,AnyTenant
    .ROLE
        CIPP.Scheduler.Read
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $APIName = $Request.Params.CIPPEndpoint
    $Headers = $Request.Headers
    Write-LogMessage -headers $Headers -API $APIName -message 'Accessed this API' -Sev 'Debug'

    # Get parameters from the request
    $RowKey = $Request.Query.RowKey ?? $Request.Body.RowKey

    # Validate required parameters
    if (-not $RowKey) {
        Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
                StatusCode = [HttpStatusCode]::BadRequest
                Body       = "Required parameter 'RowKey' is missing"
            })
        return
    }

    # Retrieve the task information
    $TaskTable = Get-CIPPTable -TableName 'ScheduledTasks'
    $Task = Get-CIPPAzDataTableEntity @TaskTable -Filter "RowKey eq '$RowKey' and PartitionKey eq 'ScheduledTask'" | Select-Object Name, TaskState, Command, Parameters, Recurrence, ExecutedTime, ScheduledTime, PostExecution, Tenant, Hidden, Results, Timestamp

    if (-not $Task) {
        Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
                StatusCode = [HttpStatusCode]::NotFound
                Body       = "Task with RowKey '$RowKey' not found"
            })
        return
    }

    # Process the task (similar to the way it's done in Invoke-ListScheduledItems)
    if ($Task.Parameters) {
        $Task.Parameters = $Task.Parameters | ConvertFrom-Json -ErrorAction SilentlyContinue
    } else {
        $Task | Add-Member -NotePropertyName Parameters -NotePropertyValue @{}
    }

    if ($Task.Recurrence -eq 0 -or [string]::IsNullOrEmpty($Task.Recurrence)) {
        $Task.Recurrence = 'Once'
    }

    try {
        $Task.ExecutedTime = [DateTimeOffset]::FromUnixTimeSeconds($Task.ExecutedTime).UtcDateTime
    } catch {}

    try {
        $Task.ScheduledTime = [DateTimeOffset]::FromUnixTimeSeconds($Task.ScheduledTime).UtcDateTime
    } catch {}

    # Get the results if available
    $ResultsTable = Get-CIPPTable -TableName 'ScheduledTaskResults'
    $ResultsFilter = "PartitionKey eq '$RowKey'"

    $Results = Get-CIPPAzDataTableEntity @ResultsTable -Filter $ResultsFilter

    if (!$Results) {
        $ResultData = ($Task.Results | ConvertFrom-Json -ErrorAction SilentlyContinue) ?? $Task.Results
        $Results = @(
            [PSCustomObject]@{
                RowKey    = $Task.Tenant
                Results   = $ResultData
                Timestamp = $Task.Timestamp
            }
        )
    }
    # Process the results if they exist
    $ProcessedResults = [System.Collections.Generic.List[object]]::new()
    foreach ($Result in $Results) {
        try {
            if ($Result.Results) {
                $ParsedResults = ($Result.Results | ConvertFrom-Json -ErrorAction SilentlyContinue) ?? $Result.Results
                if (!$ParsedResults -or 'null' -eq $ParsedResults) {
                    $Result.Results = @()
                } else {
                    $Result.Results = @($ParsedResults)
                }
                # Store tenant information with the result
                $TenantId = $Result.RowKey
                $TenantInfo = Get-Tenants -TenantFilter $TenantId -ErrorAction SilentlyContinue
                if ($TenantInfo) {
                    $Result | Add-Member -NotePropertyName TenantName -NotePropertyValue $TenantInfo.displayName -Force
                    $Result | Add-Member -NotePropertyName TenantDefaultDomain -NotePropertyValue $TenantInfo.defaultDomainName -Force
                    $Result | Add-Member -NotePropertyName TenantId -NotePropertyValue $TenantInfo.customerId -Force
                }
            }
        } catch {
            Write-LogMessage -API $APIName -message "Error processing results for task $RowKey with tenant $($Result.RowKey): $_" -Sev 'Error'
        }
        $EndResult = $Result | Select-Object Timestamp, @{n = 'Tenant'; Expression = { $_.RowKey } }, Results
        $ProcessedResults.Add($EndResult)
    }

    # Combine task and results into one response
    $Response = ConvertTo-Json -Depth 100 -InputObject @{
        Task    = $Task
        Details = $ProcessedResults
    }

    # Return the response
    Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
            StatusCode = [HttpStatusCode]::OK
            Body       = $Response
        })
}
