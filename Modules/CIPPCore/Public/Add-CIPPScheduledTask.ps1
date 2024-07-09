function Add-CIPPScheduledTask {
    [CmdletBinding()]
    param(
        [pscustomobject]$Task,
        [bool]$Hidden,
        $DisallowDuplicateName = $false,
        [string]$SyncType = $null
    )

    $Table = Get-CIPPTable -TableName 'ScheduledTasks'
    if ($DisallowDuplicateName) {
        $Filter = "PartitionKey eq 'ScheduledTask' and Name eq '$($Task.Name)'"
        $ExistingTask = (Get-CIPPAzDataTableEntity @Table -Filter $Filter)
        if ($ExistingTask) {
            return "Task with name $($Task.Name) already exists"
        }
    }

    $propertiesToCheck = @('Webhook', 'Email', 'PSA')
    $PostExecution = ($propertiesToCheck | Where-Object { $task.PostExecution.$_ -eq $true }) -join ','
    $Parameters = [System.Collections.Hashtable]@{}
    foreach ($Key in $task.Parameters.Keys) {
        $Param = $task.Parameters.$Key
        if ($Param.Key) {
            $ht = @{}
            foreach ($p in $Param) {
                Write-Host $p.Key
                $ht[$p.Key] = $p.Value
            }
            $Parameters[$Key] = [PSCustomObject]$ht
        } else {
            $Parameters[$Key] = $Param
        }
    }
    $Parameters = ($Parameters | ConvertTo-Json -Depth 10 -Compress)
    $AdditionalProperties = [System.Collections.Hashtable]@{}
    foreach ($Prop in $task.AdditionalProperties) {
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

    $entity = @{
        PartitionKey         = [string]'ScheduledTask'
        TaskState            = [string]'Planned'
        RowKey               = [string]$RowKey
        Tenant               = [string]$task.TenantFilter
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
    if ($SyncType) {
        $entity.SyncType = $SyncType
    }
    try {
        Add-CIPPAzDataTableEntity @Table -Entity $entity -Force
    } catch {
        return "Could not add task: $($_.Exception.Message)"
    }
    return "Successfully added task: $($entity.Name)"
}
