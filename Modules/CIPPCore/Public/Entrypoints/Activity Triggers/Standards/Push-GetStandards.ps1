function Push-GetStandards {
    <#
    .FUNCTIONALITY
    Entrypoint
    #>
    Param($Item)

    $Params = $Item.StandardParams | ConvertTo-Json | ConvertFrom-Json -AsHashtable
    Write-Host "My params are $($Params | ConvertTo-Json -Depth 5 -Compress)"
    try {
        $AllTasks = Get-CIPPStandards @Params
        Write-Host "AllTasks: $($AllTasks | ConvertTo-Json -Depth 5 -Compress)"
        foreach ($task in $AllTasks) {
            [PSCustomObject]@{
                Tenant       = $task.Tenant
                Standard     = $task.Standard
                Settings     = $task.Settings
                QueueId      = $Item.QueueId
                QueueName    = '{0} - {1}' -f $task.Standard, $Task.Tenant
                FunctionName = 'CIPPStandard'
            }
        }
    } catch {
        Write-Host "GetStandards Exception $($_.Exception.Message)"
    }

}
