function Push-CIPPOffboardingComplete {
    <#
    .SYNOPSIS
        Post-execution handler for offboarding orchestration completion

    .DESCRIPTION
        Updates the scheduled task state when offboarding completes

    .FUNCTIONALITY
        Entrypoint
    #>
    [CmdletBinding()]
    param($Item)

    $TaskInfo = $Item.Parameters.TaskInfo
    $TenantFilter = $Item.Parameters.TenantFilter
    $Username = $Item.Parameters.Username
    $Results = $Item.Results  # Results come from orchestrator, not Parameters

    try {
        Write-Information "Completing offboarding orchestration for $Username in tenant $TenantFilter"
        Write-Information "Raw results from orchestrator: $($Results | ConvertTo-Json -Depth 10)"

        # Flatten nested arrays from orchestrator results
        # Activity functions may return arrays like [result, "status message"]
        $FlattenedResults = @(
            foreach ($BatchResult in $Results) {
                if ($BatchResult -is [array] -and $BatchResult.Count -gt 0) {
                    Write-Information "Result is array with $($BatchResult.Count) elements, extracting elements"
                    # Output all elements from the array
                    foreach ($element in $BatchResult) {
                        if ($null -ne $element -and $element -ne '') {
                            $element
                        }
                    }
                } elseif ($null -ne $BatchResult -and $BatchResult -ne '') {
                    # Single item - output it
                    $BatchResult
                }
            }
        )

        # Process results in the same way as Push-ExecScheduledCommand
        if ($FlattenedResults.Count -eq 0) {
            $ProcessedResults = "Offboarding completed successfully for $Username"
        } else {
            Write-Information "Processing $($FlattenedResults.Count) flattened results: $($FlattenedResults | ConvertTo-Json -Depth 10)"

            # Normalize results format
            if ($FlattenedResults -is [string]) {
                $ProcessedResults = @{ Results = $FlattenedResults }
            } elseif ($FlattenedResults -is [array]) {
                # Filter and process string or resultText items
                $StringResults = $FlattenedResults | Where-Object { $_ -is [string] -or $_.resultText -is [string] }
                if ($StringResults) {
                    $ProcessedResults = $StringResults | ForEach-Object {
                        $Message = if ($_ -is [string]) { $_ } else { $_.resultText }
                        @{ Results = $Message }
                    }
                } else {
                    # Keep structured results as-is
                    $ProcessedResults = $FlattenedResults
                }
            } else {
                $ProcessedResults = $FlattenedResults
            }
        }

        Write-Information "Results after processing: $($ProcessedResults | ConvertTo-Json -Depth 10)"

        # Prepare results for storage
        if ($ProcessedResults -is [string]) {
            $StoredResults = $ProcessedResults
        } else {
            $ProcessedResults = $ProcessedResults | Select-Object * -ExcludeProperty RowKey, PartitionKey
            $StoredResults = $ProcessedResults | ConvertTo-Json -Compress -Depth 20 | Out-String
        }

        if ($TaskInfo) {
            # Update scheduled task to completed state
            $Table = Get-CippTable -tablename 'ScheduledTasks'
            $currentUnixTime = [int64](([datetime]::UtcNow) - (Get-Date '1/1/1970')).TotalSeconds

            # Check if results are too large and need separate storage
            if ($StoredResults.Length -gt 64000) {
                Write-Information 'Results exceed 64KB limit. Storing in ScheduledTaskResults table.'
                $TaskResultsTable = Get-CippTable -tablename 'ScheduledTaskResults'
                $TaskResults = @{
                    PartitionKey = $TaskInfo.RowKey
                    RowKey       = $TenantFilter
                    Results      = [string](ConvertTo-Json -Compress -Depth 20 $ProcessedResults)
                }
                $null = Add-CIPPAzDataTableEntity @TaskResultsTable -Entity $TaskResults -Force
                $StoredResults = @{ Results = 'Offboarding completed, details are available in the More Info pane' } | ConvertTo-Json -Compress
            }

            $null = Update-AzDataTableEntity -Force @Table -Entity @{
                PartitionKey = $TaskInfo.PartitionKey
                RowKey       = $TaskInfo.RowKey
                Results      = "$StoredResults"
                ExecutedTime = "$currentUnixTime"
                TaskState    = 'Completed'
            }

            Write-LogMessage -API 'Offboarding' -tenant $TenantFilter -message "Offboarding completed successfully for $Username" -sev Info

            # Send post-execution alerts if configured
            if ($TaskInfo.PostExecution -and $ProcessedResults) {
                Send-CIPPScheduledTaskAlert -Results $ProcessedResults -TaskInfo $TaskInfo -TenantFilter $TenantFilter
            }
        }

        return "Offboarding completed for $Username"

    } catch {
        $ErrorMsg = "Failed to complete offboarding for $Username : $($_.Exception.Message)"
        Write-LogMessage -API 'Offboarding' -tenant $TenantFilter -message $ErrorMsg -sev Error
        throw $ErrorMsg
    }
}
