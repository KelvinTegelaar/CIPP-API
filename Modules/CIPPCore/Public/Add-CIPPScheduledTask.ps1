function Add-CIPPScheduledTask {
    [CmdletBinding()]
    param(
        [pscustomobject]$Task,
        [bool]$Hidden
    )

    $Table = Get-CIPPTable -TableName 'ScheduledTasks'
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
    $entity = @{
        PartitionKey         = [string]'ScheduledTask'
        TaskState            = [string]'Planned'
        RowKey               = [string]$RowKey
        Tenant               = [string]$task.TenantFilter
        Name                 = [string]$task.Name
        Command              = [string]$task.Command.value
        Parameters           = [string]$Parameters
        ScheduledTime        = [string]$task.ScheduledTime
        Recurrence           = [string]$task.Recurrence.value
        PostExecution        = [string]$PostExecution
        AdditionalProperties = [string]$AdditionalProperties
        Hidden               = [bool]$Hidden
        Results              = 'Planned'
    }
    try {
        Add-CIPPAzDataTableEntity @Table -Entity $entity -Force
    } catch {
        return "Could not add task: $($_.Exception.Message)"
    }
    return 'Successfully added task'
}