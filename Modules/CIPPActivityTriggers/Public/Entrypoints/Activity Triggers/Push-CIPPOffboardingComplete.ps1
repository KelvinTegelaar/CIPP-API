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
    $Headers = $Item.Parameters.Headers
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

            Write-LogMessage -API 'Offboarding' -tenant $TenantFilter -message "Offboarding completed successfully for $Username" -sev Info -headers $Headers

            # Send post-execution alerts if configured, and keep each delivery outcome with the task and
            # on the progress row, so a failed webhook, email or PSA note is as visible as a failed step.
            if ($TaskInfo.PostExecution -and $ProcessedResults) {
                $DeploymentId = $Item.Parameters.DeploymentId
                # The notification steps have been on the row since the job started; show them running
                # while the deliveries are made, then fill each one in by title.
                $NotifyIndexes = @{}
                if ($DeploymentId) {
                    $Row = Get-CIPPAsyncDeployment -JobId $DeploymentId | Where-Object { $_.Name -eq $Username }
                    $RowSteps = @($Row.Steps)
                    for ($i = 0; $i -lt $RowSteps.Count; $i++) {
                        if ($RowSteps[$i].Kind -eq 'notify') {
                            $NotifyIndexes[[string]$RowSteps[$i].Title] = $i
                            Set-CIPPAsyncDeploymentStep -JobId $DeploymentId -Name $Username -StepIndex $i -StepStatus 'running' -Message 'Sending'
                        }
                    }
                }

                $PostExecutionResults = @(Send-CIPPScheduledTaskAlert -Results $ProcessedResults -TaskInfo $TaskInfo -TenantFilter $TenantFilter -TaskType 'User Offboarding')
                $null = Update-AzDataTableEntity -Force @Table -Entity @{
                    PartitionKey         = $TaskInfo.PartitionKey
                    RowKey               = $TaskInfo.RowKey
                    PostExecutionResults = [string](ConvertTo-Json -Compress -Depth 5 -InputObject $PostExecutionResults)
                }

                if ($DeploymentId) {
                    # One step per channel; the PSA channel can make several deliveries (per-user tickets).
                    $Covered = @{}
                    foreach ($Group in ($PostExecutionResults | Group-Object -Property Channel)) {
                        $Title = "Notify via $($Group.Name)"
                        $Message = @($Group.Group | ForEach-Object { [string]$_.Result }) -join "`n"
                        # Skipped = asked for and not delivered, so it fails the step.
                        $NotifyStatus = if (@($Group.Group | Where-Object { [string]$_.Result -match '^(Error|Could not|Failed|Skipped)' }).Count -gt 0) { 'failed' } else { 'succeeded' }
                        if ($NotifyIndexes.ContainsKey($Title)) {
                            $Covered[$Title] = $true
                            Set-CIPPAsyncDeploymentStep -JobId $DeploymentId -Name $Username -StepIndex $NotifyIndexes[$Title] -StepStatus $NotifyStatus -Message $Message
                        } else {
                            Add-CIPPAsyncDeploymentStep -JobId $DeploymentId -Name $Username -Title $Title -StepStatus $NotifyStatus -Message $Message -Kind 'notify'
                        }
                    }
                    # A channel that produced no delivery at all (the sender gave up before reaching it)
                    foreach ($Title in @($NotifyIndexes.Keys | Where-Object { -not $Covered.ContainsKey($_) })) {
                        Set-CIPPAsyncDeploymentStep -JobId $DeploymentId -Name $Username -StepIndex $NotifyIndexes[$Title] -StepStatus 'failed' -Message 'No delivery was attempted'
                    }
                }
            }
        }
        if ($Item.Parameters.DeploymentId) {
            # Close the live-progress row: failed when any step failed, otherwise succeeded.
            $Row = Get-CIPPAsyncDeployment -JobId $Item.Parameters.DeploymentId | Where-Object { $_.Name -eq $Username }
            $FinalStatus = if (@($Row.Steps | Where-Object { $_.Status -eq 'failed' }).Count -gt 0) { 'failed' } else { 'succeeded' }
            Set-CIPPAsyncDeploymentStatus -JobId $Item.Parameters.DeploymentId -Name $Username -Status $FinalStatus -Logs $StoredResults
        }
        Write-LogMessage -API 'Offboarding' -tenant $TenantFilter -message "Offboarding completed for $Username" -sev Info -headers $Headers
        return "Offboarding completed for $Username"

    } catch {
        $ErrorMsg = "Failed to complete offboarding for $Username : $($_.Exception.Message)"
        Write-LogMessage -API 'Offboarding' -tenant $TenantFilter -message $ErrorMsg -sev Error -headers $Headers -LogData (Get-CippException -Exception $_)
        if ($Item.Parameters.DeploymentId) {
            Set-CIPPAsyncDeploymentStatus -JobId $Item.Parameters.DeploymentId -Name $Username -Status 'failed' -Logs $ErrorMsg
        }
        throw $ErrorMsg
    }
}
