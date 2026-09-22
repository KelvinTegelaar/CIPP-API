function Add-CIPPScheduledTask {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $false)]
        [pscustomobject]$Task,

        [Parameter(Mandatory = $false)]
        [bool]$Hidden,

        [Parameter(Mandatory = $false)]
        $DisallowDuplicateName = $false,

        [Parameter(Mandatory = $false)]
        [string]$SyncType = $null,

        [Parameter(Mandatory = $false)]
        [switch]$RunNow,

        [Parameter(Mandatory = $false)]
        [string]$RowKey = $null,

        [Parameter(Mandatory = $false)]
        [string]$DesiredStartTime = $null,

        [Parameter(Mandatory = $false)]
        $Headers
    )

    try {

        $Table = Get-CIPPTable -TableName 'ScheduledTasks'

        if ($RunNow.IsPresent -and $RowKey) {
            try {
                $Filter = "PartitionKey eq 'ScheduledTask' and RowKey eq '$($RowKey)'"
                $ExistingTask = (Get-CIPPAzDataTableEntity @Table -Filter $Filter)
                $ExistingTask.ScheduledTime = [int64](([datetime]::UtcNow) - (Get-Date '1/1/1970')).TotalSeconds
                $ExistingTask.TaskState = 'Planned'
                Add-CIPPAzDataTableEntity @Table -Entity $ExistingTask -Force
                Write-LogMessage -headers $Headers -API 'RunNow' -message "Task $($ExistingTask.Name) scheduled to run now" -Sev 'Info' -Tenant $ExistingTask.Tenant
                # Add-CippQueueMessage returns $true; without discarding it the caller's Results array shows a bare 'true'
                $null = Add-CippQueueMessage -Cmdlet 'Start-UserTasksOrchestrator' -Parameters @{
                    TaskId = $RowKey
                }
                return "Task $($ExistingTask.Name) scheduled to run now"
            } catch {
                $ErrorMessage = Get-NormalizedError -Message $_.Exception.Message
                Write-LogMessage -headers $Headers -API 'RunNow' -message "Could not run task: $ErrorMessage" -Sev 'Error'
                return "Could not run task: $ErrorMessage"
            }
        } else {
            if (!$Task.RowKey) {
                $RowKey = (New-Guid).Guid
            } else {
                $RowKey = $Task.RowKey
            }

            if ($DisallowDuplicateName) {
                $Filter = "PartitionKey eq 'ScheduledTask' and Name eq '$($Task.Name)' and TaskState ne 'Completed' and TaskState ne 'Failed'"
                $ExistingTask = (Get-CIPPAzDataTableEntity @Table -Filter $Filter)
                if ($ExistingTask) {
                    return "Error - A scheduled task named '$($Task.Name)' already exists and was not created again."
                }
            }

            $RequestedCommand = $task.Command.value ?? $task.Command

            # Validate the command exists — on HttpOnly workers sibling modules aren't loaded,
            # so import them temporarily for validation (actual execution runs on activity workers)
            $Command = Get-Command $RequestedCommand -ErrorAction SilentlyContinue
            $ImportedModules = [System.Collections.Generic.List[string]]::new()
            if (-not $Command) {
                try {
                    foreach ($SiblingModule in @('CIPPStandards', 'CIPPAlerts', 'CIPPTests', 'CIPPDB', 'CippExtensions', 'CIPPActivityTriggers')) {
                        if (-not (Get-Module -Name $SiblingModule)) {
                            Import-Module $SiblingModule -ErrorAction SilentlyContinue
                            if (Get-Module -Name $SiblingModule) {
                                $ImportedModules.Add($SiblingModule)
                            }
                        }
                    }
                    $Command = Get-Command $RequestedCommand -ErrorAction SilentlyContinue
                } finally {
                    foreach ($Imported in $ImportedModules) {
                        Remove-Module $Imported -ErrorAction SilentlyContinue
                    }
                }
            }

            if (!$Command) {
                Write-LogMessage -headers $Headers -API 'ScheduledTask' -message "Blocked attempt to schedule non-existent command: $RequestedCommand" -Sev 'Warning'
                return "Error - The command '$RequestedCommand' does not exist and cannot be scheduled."
            }

            if ($Command.Module -notin @('CIPPCore', 'CIPPAlerts', 'CIPPStandards', 'CIPPTests', 'CIPPDB', 'CippExtensions', 'CIPPActivityTriggers')) {
                Write-LogMessage -headers $Headers -API 'ScheduledTask' -message "Blocked attempt to schedule command from unauthorized module: $($Command.ModuleName)\$RequestedCommand" -Sev 'Warning'
                return "Error - The command '$RequestedCommand' is not permitted to run as a scheduled task."
            }

            if ($RequestedCommand -in (Get-CIPPSchedulerBlockedCommands)) {
                Write-LogMessage -headers $Headers -API 'ScheduledTask' -message "Blocked attempt to schedule restricted command: $RequestedCommand" -Sev 'Warning'
                return "Error - The command '$RequestedCommand' is not permitted to run as a scheduled task."
            }

            $propertiesToCheck = @('Webhook', 'Email', 'PSA')
            $PostExecutionObject = ($propertiesToCheck | Where-Object { $task.PostExecution.$_ -eq $true })
            $PostExecution = $PostExecutionObject ? @($PostExecutionObject -join ',') : ($Task.PostExecution.value -join ',')
            $Parameters = [System.Collections.Hashtable]@{}
            foreach ($Key in $task.Parameters.PSObject.Properties.Name) {
                $Param = $task.Parameters.$Key

                if ($null -eq $Param -or $Param -eq '' -or ($Param | Measure-Object).Count -eq 0) {
                    continue
                }

                # handle different object types in params
                if ($Param -is [System.Collections.IDictionary] -or $Param[0].Key) {
                    Write-Information "Parameter $Key is a hashtable"
                    $ht = @{}
                    foreach ($p in $Param.GetEnumerator()) {
                        $ht[$p.Key] = $p.Value
                    }
                    $Parameters[$Key] = [PSCustomObject]$ht
                    Write-Information "Converted $Key to PSObject $($Parameters[$Key] | ConvertTo-Json -Compress)"
                } elseif ($Param -is [System.Object[]] -and -not ($Param -is [string])) {
                    Write-Information "Parameter $Key is an enumerable object"
                    $Param = $Param | ForEach-Object {
                        if ($null -eq $_) {
                            # Skip null entries
                            return
                        }
                        if ($_ -is [System.Collections.IDictionary]) {
                            [PSCustomObject]$_
                        } elseif ($_ -is [PSCustomObject]) {
                            $_
                        } else {
                            $_
                        }
                    } | Where-Object { $null -ne $_ }
                    $Parameters[$Key] = $Param
                } else {
                    Write-Information "Parameter $Key is a simple value"
                    $Parameters[$Key] = $Param
                }
            }

            if ($Headers) {
                $Parameters.Headers = $Headers | Select-Object -Property 'x-forwarded-for', 'x-ms-client-principal', 'x-ms-client-principal-idp', 'x-ms-client-principal-name'
            }

            $AdditionalProperties = [System.Collections.Hashtable]@{}
            foreach ($Prop in $task.AdditionalProperties) {
                if ($null -eq $Prop.Value -or $Prop.Value -eq '' -or ($Prop.Value | Measure-Object).Count -eq 0) {
                    continue
                }
                $AdditionalProperties[$Prop.Key] = $Prop.Value
            }
            $AdditionalProperties = ([PSCustomObject]$AdditionalProperties | ConvertTo-Json -Compress)


            $Recurrence = if ([string]::IsNullOrEmpty($task.Recurrence.value)) {
                $task.Recurrence
            } else {
                $task.Recurrence.value
            }

            if ($task.PSObject.Properties.Name -notcontains 'ScheduledTime') {
                $task | Add-Member -MemberType NoteProperty -Name 'ScheduledTime' -Value 0 -Force
            }

            if ($DesiredStartTime) {
                try {
                    # Parse the epoch time
                    $epochSeconds = [int64]$DesiredStartTime
                    # Set ScheduledTime to the desired time
                    $task.ScheduledTime = $epochSeconds
                } catch {
                    Write-Warning "Failed to parse DesiredStartTime: $DesiredStartTime. Using provided ScheduledTime."
                    # Fall back to default
                    if ([int64]$task.ScheduledTime -eq 0 -or [string]::IsNullOrEmpty($task.ScheduledTime)) {
                        $task.ScheduledTime = [int64](([datetime]::UtcNow) - (Get-Date '1/1/1970')).TotalSeconds
                    }
                }
            } else {
                # No DesiredStartTime - use current behavior (immediate execution)
                if ([int64]$task.ScheduledTime -eq 0 -or [string]::IsNullOrEmpty($task.ScheduledTime)) {
                    $task.ScheduledTime = [int64](([datetime]::UtcNow) - (Get-Date '1/1/1970')).TotalSeconds
                }
            }
            # Split exclusions by type (same pattern as Tenant/TenantGroup): plain tenants are
            # comma-joined, groups are stored as JSON and expanded at runtime by the orchestrator
            $ExcludedEntries = @($task.excludedTenants | Where-Object { $_.value })
            $excludedTenants = @($ExcludedEntries | Where-Object { $_.type -ne 'Group' }).value -join ','
            $ExcludedGroupEntries = @($ExcludedEntries | Where-Object { $_.type -eq 'Group' } | ForEach-Object {
                    [PSCustomObject]@{ value = $_.value; label = $_.label; type = 'Group' }
                })
            $excludedTenantGroups = if ($ExcludedGroupEntries.Count -gt 0) {
                ConvertTo-Json -InputObject $ExcludedGroupEntries -Compress -Depth 5
            }

            # Handle tenant filter - support both single tenant and tenant groups
            $tenantFilter = $task.TenantFilter.value ? $task.TenantFilter.value : $task.TenantFilter
            $originalTenantFilter = $task.TenantFilter

            # If tenant filter is a complex object (from form), extract the value
            if ($tenantFilter -is [PSCustomObject] -and $tenantFilter.value) {
                $originalTenantFilter = $tenantFilter
                $tenantFilter = $tenantFilter.value
            }

            # If tenant filter is a string but still seems to be JSON, try to parse it
            if ($tenantFilter -is [string] -and $tenantFilter.StartsWith('{')) {
                try {
                    $parsedTenantFilter = $tenantFilter | ConvertFrom-Json
                    if ($parsedTenantFilter.value) {
                        $originalTenantFilter = $parsedTenantFilter
                        $tenantFilter = $parsedTenantFilter.value
                    }
                } catch {
                    # If parsing fails, use the string as is
                    Write-Warning "Could not parse tenant filter JSON: $tenantFilter"
                }
            }

            # Stored parameters are user input: strip any tenant-identifying parameter so the
            # authorized task tenant is injected at execution instead of a stored value, and log
            # when the stored value pointed somewhere other than the picked tenant.
            foreach ($TenantParamName in @('TenantFilter', 'Tenant', 'TenantId')) {
                if (-not $Parameters.ContainsKey($TenantParamName)) { continue }
                $StoredTenantValue = $Parameters[$TenantParamName]
                $StoredTenantString = [string]($StoredTenantValue.value ?? $StoredTenantValue)
                if (![string]::IsNullOrWhiteSpace($StoredTenantString) -and $StoredTenantString -ne [string]$tenantFilter) {
                    Write-LogMessage -headers $Headers -API 'ScheduledTask' -message "Task $($task.Name): parameter -$TenantParamName value '$StoredTenantString' does not match the selected tenant '$tenantFilter' and was removed; the task runs against the selected tenant." -Sev 'Error' -Tenant $tenantFilter
                }
                $Parameters.Remove($TenantParamName)
            }

            $Parameters = ($Parameters | ConvertTo-Json -Depth 10 -Compress)
            if ($Parameters -eq 'null') { $Parameters = '' }

            $entity = @{
                PartitionKey         = [string]'ScheduledTask'
                TaskState            = [string]'Planned'
                RowKey               = [string]$RowKey
                Tenant               = [string]$tenantFilter
                excludedTenants      = [string]$excludedTenants
                excludedTenantGroups = [string]$excludedTenantGroups
                Name                 = [string]$task.Name
                Command              = [string]$RequestedCommand
                Parameters           = [string]$Parameters
                ScheduledTime        = [string]$task.ScheduledTime
                Recurrence           = [string]$Recurrence
                PostExecution        = [string]$PostExecution
                Reference            = [string]$task.Reference
                AdditionalProperties = [string]$AdditionalProperties
                Hidden               = [bool]$Hidden
                Results              = 'Planned'
                AlertComment         = [string]$task.AlertComment
                CustomSubject        = [string]$task.CustomSubject
                PsaTicketStrategy    = [string]($task.PsaTicketStrategy.value ?? $task.PsaTicketStrategy)
                PsaTicketPriority    = [string]($task.PsaTicketPriority.value ?? $task.PsaTicketPriority)
                PsaTicketId          = [string]($task.PsaTicketId.value ?? $task.PsaTicketId)
            }


            if ($task.Tag) {
                $entity['Tag'] = [string]$task.Tag
            }

            if ($Task.RowKey) {
                # Editing replaces the entity, so carry the disabled state over to keep a disabled task disabled
                $ExistingEntity = Get-CIPPAzDataTableEntity @Table -Filter "PartitionKey eq 'ScheduledTask' and RowKey eq '$RowKey'" -Property RowKey, Disabled
                if ($ExistingEntity.Disabled -eq $true) {
                    $entity['Disabled'] = $true
                }
            }

            # Always store DesiredStartTime if provided
            if ($DesiredStartTime) {
                $entity['DesiredStartTime'] = [string]$DesiredStartTime
            }

            # Store the original tenant filter for group expansion during execution
            if ($originalTenantFilter -is [PSCustomObject] -and $originalTenantFilter.type -eq 'Group') {
                $entity['TenantGroup'] = [string]($originalTenantFilter | ConvertTo-Json -Compress)
            } elseif ($originalTenantFilter -is [string] -and $originalTenantFilter.StartsWith('{')) {
                # Check if it's a serialized group object
                try {
                    $parsedOriginal = $originalTenantFilter | ConvertFrom-Json
                    if ($parsedOriginal.type -eq 'Group') {
                        $entity['TenantGroup'] = [string]$originalTenantFilter
                    }
                } catch {
                    # Not a JSON object, ignore
                }
            }

            # Stored verbatim so the orchestrator expands groups at run time. The version marker tells
            # it excludedTenants holds only the operator's picks, not a snapshot of unselected tenants.
            if ($task.Tenants) {
                $entity['Tenants'] = $task.Tenants -is [string] ? [string]$task.Tenants : [string]($task.Tenants | ConvertTo-Json -Compress -Depth 10)
                $entity['TenantSelectionVersion'] = 2
            }

            if ($task.Trigger) {
                $entity.Trigger = [string]($task.Trigger | ConvertTo-Json -Compress)
                $TriggerType = $task.Trigger.Type.value ?? $task.Trigger.Type
                if ($TriggerType -eq 'DeltaQuery') {
                    $Resource = $task.Trigger.DeltaResource.value ?? $task.Trigger.DeltaResource
                    $DeltaTenantFilter = if ($entity.TenantGroup) { $entity.TenantGroup | ConvertFrom-Json } else { $tenantFilter }

                    try {
                        $null = New-CIPPTaskDeltaQuery -Trigger $task.Trigger -TenantFilter $DeltaTenantFilter -PartitionKey $RowKey
                        Write-Information "Created delta query for resource $($Resource)"
                    } catch {
                        throw "Failed to create delta query for resource $($Resource): $($_.Exception.Message)"
                    }
                }
            }

            if ($SyncType) {
                $entity.SyncType = $SyncType
            }
            try {
                Add-CIPPAzDataTableEntity @Table -Entity $entity -Force
            } catch {
                $ErrorMessage = Get-NormalizedError -Message $_.Exception.Message
                Write-Information $_.InvocationInfo.PositionMessage
                Write-Information ($entity | ConvertTo-Json)
                return "Error - Could not add task: $ErrorMessage"
            }
            Write-LogMessage -headers $Headers -API 'ScheduledTask' -message "Added task $($entity.Name) with ID $($entity.RowKey)" -Sev 'Info' -Tenant $tenantFilter

            # Calculate relative time for next run
            $scheduledEpoch = [int64]$entity.ScheduledTime
            $currentTime = [datetime]::UtcNow

            if ($scheduledEpoch -eq 0 -or $scheduledEpoch -le ([int64](($currentTime) - (Get-Date '1/1/1970')).TotalSeconds)) {
                # Task will run at next 15-minute interval - calculate efficiently
                $minutesToAdd = 15 - ($currentTime.Minute % 15)
                $nextRunTime = $currentTime.AddMinutes($minutesToAdd).AddSeconds(-$currentTime.Second).AddMilliseconds(-$currentTime.Millisecond)
                $timeUntilRun = $nextRunTime - $currentTime
            } else {
                # Task is scheduled for a specific time in the future
                $scheduledTime = [datetime]'1/1/1970' + [TimeSpan]::FromSeconds($scheduledEpoch)
                $timeUntilRun = $scheduledTime - $currentTime
            }

            # Format relative time
            $relativeTime = switch ($timeUntilRun.TotalMinutes) {
                { $_ -ge 1440 } {
                    $days = [Math]::Floor($timeUntilRun.TotalDays)
                    $hours = $timeUntilRun.Hours
                    $result = "$days day$(if ($days -ne 1) { 's' })"
                    if ($hours -gt 0) { $result += " and $hours hour$(if ($hours -ne 1) { 's' })" }
                    $result
                    break
                }
                { $_ -ge 60 } {
                    $hours = [Math]::Floor($timeUntilRun.TotalHours)
                    $minutes = $timeUntilRun.Minutes
                    $result = "$hours hour$(if ($hours -ne 1) { 's' })"
                    if ($minutes -gt 0) { $result += " and $minutes minute$(if ($minutes -ne 1) { 's' })" }
                    $result
                    break
                }
                { $_ -ge 2 } { "about $([Math]::Round($_)) minutes"; break }
                { $_ -ge 1 } { 'about 1 minute'; break }
                default { 'less than a minute' }
            }

            if ($RunNow.IsPresent) {
                # Add-CippQueueMessage returns $true; without discarding it the caller's Results array shows a bare 'true'
                $null = Add-CippQueueMessage -Cmdlet 'Start-UserTasksOrchestrator' -Parameters @{
                    TaskId = $RowKey
                }
                return "Task $($entity.Name) scheduled to run now"
            }

            return "Successfully added task: $($entity.Name). It will run in $relativeTime."
        }
    } catch {
        Write-Warning "Failed to add scheduled task: $($_.Exception.Message)"
        $ErrorMessage = Get-NormalizedError -Message $_.Exception.Message
        #Write-Information ($Task | ConvertTo-Json)
        throw "Error - Could not add task: $ErrorMessage"
    }
}
