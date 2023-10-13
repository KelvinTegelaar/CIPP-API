using namespace System.Net
param($Request, $TriggerMetadata)
$APIName = $TriggerMetadata.FunctionName
Write-LogMessage -user $request.headers.'x-ms-client-principal' -API $APINAME -message 'Accessed this API' -Sev 'Debug'
$task = $Request.Body
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

$Parameters = ($Parameters | ConvertTo-Json -Compress)

$AdditionalProperties = [System.Collections.Hashtable]@{}
foreach ($Prop in $task.AdditionalProperties) {
    $AdditionalProperties[$Prop.Key] = $Prop.Value
}
$AdditionalProperties = ([PSCustomObject]$AdditionalProperties | ConvertTo-Json -Compress)


if ($Parameters -eq 'null') { $Parameters = '' }
$entity = @{
    PartitionKey         = [string]'ScheduledTask'
    TaskState            = [string]'Planned'
    RowKey               = [string]"$(New-Guid)"
    Tenant               = [string]$task.TenantFilter
    Name                 = [string]$task.Name
    Command              = [string]$task.Command.value
    Parameters           = [string]$Parameters
    ScheduledTime        = [string]$task.ScheduledTime
    Recurrence           = [string]$task.Recurrence.value
    PostExecution        = [string]$PostExecution
    AdditionalProperties = [string]$AdditionalProperties
    Results              = 'Planned'
}
Write-Host "entity: $($entity | ConvertTo-Json)"
Add-AzDataTableEntity @Table -Entity $entity
Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
        StatusCode = [HttpStatusCode]::OK
        Body       = @{ Results = 'Task added successfully.' }
    })