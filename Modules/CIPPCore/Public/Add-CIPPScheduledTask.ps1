function Add-CIPPScheduledTask {
    [CmdletBinding(DefaultParameterSetName = 'Default')]
    param(
        [Parameter(Mandatory = $true, ParameterSetName = 'Default')]
        [pscustomobject]$Task,

        [Parameter(Mandatory = $false, ParameterSetName = 'Default')]
        [bool]$Hidden,

        [Parameter(Mandatory = $false, ParameterSetName = 'Default')]
        $DisallowDuplicateName = $false,

        [Parameter(Mandatory = $false, ParameterSetName = 'Default')]
        [string]$SyncType = $null,

        [Parameter(Mandatory = $false, ParameterSetName = 'RunNow')]
        [switch]$RunNow,

        [Parameter(Mandatory = $true, ParameterSetName = 'RunNow')]
        [string]$RowKey,

        [Parameter(Mandatory = $false, ParameterSetName = 'Default')]
        [Parameter(Mandatory = $false, ParameterSetName = 'RunNow')]
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
                return "Task $($ExistingTask.Name) scheduled to run now"
            } catch {
                $ErrorMessage = Get-NormalizedError -Message $_.Exception.Message
                Write-LogMessage -headers $Headers -API 'RunNow' -message "Could not run task: $ErrorMessage" -Sev 'Error'
                return "Could not run task: $ErrorMessage"
            }
        } else {
            if ($DisallowDuplicateName) {
                $Filter = "PartitionKey eq 'ScheduledTask' and Name eq '$($Task.Name)'"
                $ExistingTask = (Get-CIPPAzDataTableEntity @Table -Filter $Filter)
                if ($ExistingTask) {
                    return "Task with name $($Task.Name) already exists"
                }
            }

            $propertiesToCheck = @('Webhook', 'Email', 'PSA')
            $PostExecutionObject = ($propertiesToCheck | Where-Object { $task.PostExecution.$_ -eq $true })
            $PostExecution = $PostExecutionObject ? ($PostExecutionObject -join ',') : ($Task.PostExecution.value -join ',')
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

            $Parameters = ($Parameters | ConvertTo-Json -Depth 10 -Compress)
            $AdditionalProperties = [System.Collections.Hashtable]@{}
            foreach ($Prop in $task.AdditionalProperties) {
                if ($null -eq $Prop.Value -or $Prop.Value -eq '' -or ($Prop.Value | Measure-Object).Count -eq 0) {
                    continue
                }
                $AdditionalProperties[$Prop.Key] = $Prop.Value
            }
            $AdditionalProperties = ([PSCustomObject]$AdditionalProperties | ConvertTo-Json -Compress)
            if ($Parameters -eq 'null') { $Parameters = '' }
            if (!$Task.RowKey) {
                $RowKey = (New-Guid).Guid
            } else {
                $RowKey = $Task.RowKey
            }

            $Recurrence = if ([string]::IsNullOrEmpty($task.Recurrence.value)) {
                $task.Recurrence
            } else {
                $task.Recurrence.value
            }

            if ([int64]$task.ScheduledTime -eq 0 -or [string]::IsNullOrEmpty($task.ScheduledTime)) {
                $task.ScheduledTime = [int64](([datetime]::UtcNow) - (Get-Date '1/1/1970')).TotalSeconds
            }
            $excludedTenants = if ($task.excludedTenants.value) {
                $task.excludedTenants.value -join ','
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

            $entity = @{
                PartitionKey         = [string]'ScheduledTask'
                TaskState            = [string]'Planned'
                RowKey               = [string]$RowKey
                Tenant               = [string]$tenantFilter
                excludedTenants      = [string]$excludedTenants
                Name                 = [string]$task.Name
                Command              = [string]$task.Command.value
                Parameters           = [string]$Parameters
                ScheduledTime        = [string]$task.ScheduledTime
                Recurrence           = [string]$Recurrence
                PostExecution        = [string]$PostExecution
                AdditionalProperties = [string]$AdditionalProperties
                Hidden               = [bool]$Hidden
                Results              = 'Planned'
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
            if ($SyncType) {
                $entity.SyncType = $SyncType
            }
            try {
                Add-CIPPAzDataTableEntity @Table -Entity $entity -Force
            } catch {
                $ErrorMessage = Get-NormalizedError -Message $_.Exception.Message
                return "Could not add task: $ErrorMessage"
            }
            return "Successfully added task: $($entity.Name)"
        }
    } catch {
        Write-Warning "Failed to add scheduled task: $($_.Exception.Message)"
        Write-Information $_.InvocationInfo.PositionMessage
        $ErrorMessage = Get-NormalizedError -Message $_.Exception.Message
        throw "Could not add task: $ErrorMessage"
    }
}
