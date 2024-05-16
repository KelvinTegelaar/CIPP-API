function Push-GetStandards {
    <#
    .FUNCTIONALITY
    Entrypoint
    #>
    Param($Item)

    $Params = $Item.StandardParams | ConvertTo-Json | ConvertFrom-Json -AsHashtable
    try {
        $AllTasks = Get-CIPPStandards @Params
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