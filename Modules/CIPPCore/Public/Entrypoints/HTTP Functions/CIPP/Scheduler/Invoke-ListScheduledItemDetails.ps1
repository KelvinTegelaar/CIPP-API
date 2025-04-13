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
        try {
            # Handle the case when we need to use Task.Results
            if ($Task.Results) {
                # Try to safely parse JSON or use the raw value if parsing fails
                try {
                    if ($Task.Results -is [string]) {
                        $ResultString = $Task.Results.ToString().Trim()
                        if (($ResultString -match '^\[.*\]$') -or ($ResultString -match '^\{.*\}$')) {
                            $ResultData = $Task.Results | ConvertFrom-Json -ErrorAction Stop
                        } else {
                            # Not valid JSON format, use as is
                            $ResultData = $Task.Results
                        }
                    } else {
                        # Already an object, use as is
                        $ResultData = $Task.Results
                    }
                } catch {
                    # If JSON parsing fails, use raw value
                    Write-LogMessage -API $APIName -message "Error parsing Task.Results as JSON: $_" -Sev 'Warning'
                    $ResultData = $Task.Results
                }
            } else {
                $ResultData = $null
            }
        } catch {
            Write-LogMessage -API $APIName -message "Error processing Task.Results: $_" -Sev 'Error'
            $ResultData = $null
        }

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
            if ($null -ne $Result.Results) {
                # Safe handling based on result type
                if ($Result.Results -is [array] -or $Result.Results -is [System.Collections.ICollection]) {
                    # Already a collection, use as is
                    $ParsedResults = $Result.Results
                } elseif ($Result.Results -is [string]) {
                    $ResultString = $Result.Results.ToString().Trim()
                    # Only try to parse as JSON if it looks like JSON
                    if (($ResultString -match '^\[.*\]$') -or ($ResultString -match '^\{.*\}$')) {
                        try {
                            $ParsedResults = $Result.Results | ConvertFrom-Json -ErrorAction Stop
                        } catch {
                            Write-LogMessage -API $APIName -message "Failed to parse result as JSON: $_" -Sev 'Warning'
                            # On failure, keep as string
                            $ParsedResults = $Result.Results
                        }
                    } else {
                        # Not valid JSON format
                        $ParsedResults = $Result.Results
                    }
                } else {
                    # Any other object type
                    $ParsedResults = $Result.Results
                }

                # Ensure results is always an array
                if ($null -eq $ParsedResults -or 'null' -eq $ParsedResults) {
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
            # Set Results to an empty array to prevent further errors
            $Result.Results = @()
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
