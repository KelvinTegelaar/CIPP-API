function Get-CIPPTimerFunctions {
    [CmdletBinding()]
    param(
        [switch]$All
    )

    $ConfigTable = Get-CIPPTable -tablename Config
    $Config = Get-CIPPAzDataTableEntity @ConfigTable -Filter "PartitionKey eq 'OffloadFunctions' and RowKey eq 'OffloadFunctions'"

    $RunOnProcessor = $true
    if ($Config -and $Config.state -eq $true) {
        if ($env:CIPP_PROCESSOR -ne 'true' -and !$All.IsPresent) {
            $RunOnProcessor = $false
        }
    }

    $CIPPCoreModuleRoot = Get-Module -Name CIPPCore | Select-Object -ExpandProperty ModuleBase

    if (!('NCronTab.Advanced.CrontabSchedule' -as [type])) {
        try {
            $NCronTab = Join-Path -Path $CIPPCoreModuleRoot -ChildPath 'lib\Ncrontab.Advanced.dll'
            Add-Type -Path $NCronTab
        } catch {}
    }

    $CIPPRoot = (Get-Item $CIPPCoreModuleRoot).Parent.Parent
    $Orchestrators = Get-Content -Path $CIPPRoot\CIPPTimers.json | ConvertFrom-Json | Where-Object { $_.RunOnProcessor -eq $RunOnProcessor }
    $Table = Get-CIPPTable -TableName 'CIPPTimers'
    $OrchestratorStatus = Get-CIPPAzDataTableEntity @Table -Filter "RunOnProcessor eq $RunOnProcessor"
    foreach ($Orchestrator in $Orchestrators) {
        $Status = $OrchestratorStatus | Where-Object { $_.RowKey -eq $Orchestrator.Command }
        if ($Status.Cron) {
            $CronString = $Status.Cron
        } else {
            $CronString = $Orchestrator.Cron
        }
        $CronCount = ($CronString -split ' ' | Measure-Object).Count
        if ($CronCount -eq 5) {
            $Cron = [Ncrontab.Advanced.CrontabSchedule]::Parse($CronString)
        } elseif ($CronCount -eq 6) {
            $Cron = [Ncrontab.Advanced.CrontabSchedule]::Parse($CronString, [Ncrontab.Advanced.Enumerations.CronStringFormat]::WithSeconds)
        } else {
            Write-Warning "Invalid cron expression for $($Orchestrator.Command): $($Orchestrator.Cron)"
            continue
        }

        $Now = Get-Date
        if ($All.IsPresent) {
            $NextOccurrence = $Cron.GetNextOccurrence($Now)
        } else {
            $NextOccurrences = $Cron.GetNextOccurrences($Now.AddMinutes(-15), $Now.AddMinutes(15))
            if ($Status.LastOccurrence -eq 'Never') {
                $NextOccurrence = $NextOccurrences[0]
            } else {
                $NextOccurrence = $NextOccurrences | Where-Object { $_ -gt $Status.LastRun } | Select-Object -First 1
                $NextOccurrence = $NextOccurrence
            }
        }

        if (Get-Command -Name $Orchestrator.Command -Module CIPPCore -ErrorAction SilentlyContinue) {
            if (!$Status) {
                $Status = [pscustomobject]@{
                    PartitionKey   = 'Timer'
                    RowKey         = $Orchestrator.Command
                    Cron           = $CronString
                    LastOccurrence = 'Never'
                    NextOccurrence = $NextOccurrence.ToUniversalTime()
                    Status         = 'Not Scheduled'
                    OrchestratorId = ''
                    RunOnProcessor = $RunOnProcessor
                    IsSystem       = $Orchestrator.IsSystem ?? $false
                }
                Add-CIPPAzDataTableEntity @Table -Entity $Status
            } else {
                if ($Orchestrator.IsSystem) {
                    $Status.Cron = $CronString
                }
                $Status.NextOccurrence = $NextOccurrence.ToUniversalTime()
                Add-CIPPAzDataTableEntity @Table -Entity $Status -Force
            }
            if ($NextOccurrence) {
                [PSCustomObject]@{
                    Command        = $Orchestrator.Command
                    Cron           = $CronString
                    NextOccurrence = $NextOccurrence.ToUniversalTime()
                    LastOccurrence = $Status.LastOccurrence
                    Status         = $Status.Status
                    OrchestratorId = $Status.OrchestratorId
                    RunOnProcessor = $Orchestrator.RunOnProcessor
                    IsSystem       = $Orchestrator.IsSystem ?? $false
                }
            }
        } else {
            if ($Status) {
                Write-Warning "Timer function: $($Orchestrator.Command) does not exist"
                Remove-CIPPAzDataTableEntity @Table -Entity $Status
            }
        }
    }
}
