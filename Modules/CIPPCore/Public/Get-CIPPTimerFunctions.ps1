function Get-CIPPTimerFunctions {
    [CmdletBinding()]
    param(
        [switch]$ResetToDefault,
        [switch]$ListAllTasks
    )

    $ConfigTable = Get-CIPPTable -tablename Config
    $Config = Get-CIPPAzDataTableEntity @ConfigTable -Filter "PartitionKey eq 'OffloadFunctions' and RowKey eq 'OffloadFunctions'"

    # Check running nodes
    $VersionTable = Get-CIPPTable -tablename 'Version'
    $Nodes = Get-CIPPAzDataTableEntity @VersionTable -Filter "PartitionKey eq 'Version' and RowKey ne 'Version' and RowKey ne 'frontend'"

    $FunctionName = $env:WEBSITE_SITE_NAME
    $MainFunctionVersion = ($Nodes | Where-Object { $_.RowKey -eq $FunctionName }).Version
    $AvailableNodes = $Nodes.RowKey | Where-Object { $_.RowKey -match '-' -and $_.Version -eq $MainFunctionVersion } | ForEach-Object { ($_ -split '-')[1] }

    # Get node name
    if ($FunctionName -match '-') {
        $Node = ($FunctionName -split '-')[1]
    } else {
        $Node = 'http'
    }

    $RunOnProcessor = $true
    if ($Config -and $Config.state -eq $true -and $AvailableNodes.Count -gt 0) {
        if ($env:CIPP_PROCESSOR -ne 'true') {
            $RunOnProcessor = $false
        }
    }

    $CIPPCoreModuleRoot = Get-Module -Name CIPPCore | Select-Object -ExpandProperty ModuleBase

    if (!('NCronTab.Advanced.CrontabSchedule' -as [type])) {
        try {
            $NCronTab = Join-Path -Path $CIPPCoreModuleRoot -ChildPath 'lib\NCrontab.Advanced.dll'
            Add-Type -Path $NCronTab
        } catch {}
    }

    $CIPPRoot = (Get-Item $CIPPCoreModuleRoot).Parent.Parent
    $CippTimers = Get-Content -Path $CIPPRoot\Resources\CIPPTimers.json

    if ($ListAllTasks) {
        $Orchestrators = $CippTimers | ConvertFrom-Json | Sort-Object -Property Priority
    } else {
        $Orchestrators = $CippTimers | ConvertFrom-Json | Where-Object { $_.RunOnProcessor -eq $RunOnProcessor } | Sort-Object -Property Priority
    }
    $Table = Get-CIPPTable -TableName 'CIPPTimers'
    $RunOnProcessorTxt = if ($RunOnProcessor) { 'true' } else { 'false' }
    if ($ListAllTasks.IsPresent) {
        $OrchestratorStatus = Get-CIPPAzDataTableEntity @Table
    } else {
        $OrchestratorStatus = Get-CIPPAzDataTableEntity @Table -Filter "RunOnProcessor eq $RunOnProcessorTxt"
    }

    $OrchestratorStatus | Where-Object { $_.RowKey -notmatch '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' } | Select-Object ETag, PartitionKey, RowKey | ForEach-Object {
        Remove-AzDataTableEntity @Table -Entity $_ -Force
    }

    foreach ($Orchestrator in $Orchestrators) {
        if (Get-Command -Name $Orchestrator.Command -Module CIPPCore -ErrorAction SilentlyContinue) {
            $Status = $OrchestratorStatus | Where-Object { $_.RowKey -eq $Orchestrator.Id }
            if ($Status.Cron -and $Orchestrator.IsSystem -eq $true -and -not $ResetToDefault.IsPresent) {
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

            if (!$ListAllTasks.IsPresent) {
                if ($Orchestrator.PreferredProcessor -and $AvailableNodes -contains $Orchestrator.PreferredProcessor -and $Node -ne $Orchestrator.PreferredProcessor) {
                    # only run on preferred processor when available
                    continue
                } elseif ((!$Orchestrator.PreferredProcessor -or $AvailableNodes -notcontains $Orchestrator.PreferredProcessor) -and $Node -notin ('http', 'proc')) {
                    # Catchall function nodes
                    continue
                }
            }

            $Now = Get-Date
            if ($ListAllTasks.IsPresent) {
                $NextOccurrence = [datetime]$Cron.GetNextOccurrence($Now)
            } else {
                $NextOccurrences = $Cron.GetNextOccurrences($Now.AddMinutes(-15), $Now.AddMinutes(15))
                if (!$Status -or $Status.LastOccurrence -eq 'Never') {
                    $NextOccurrence = $NextOccurrences | Where-Object { $_ -le (Get-Date) } | Select-Object -First 1
                } else {
                    $NextOccurrence = $NextOccurrences | Where-Object { $_ -gt $Status.LastOccurrence.DateTime.ToLocalTime() -and $_ -le (Get-Date) } | Select-Object -First 1
                }
            }


            if ($NextOccurrence -or $ListAllTasks.IsPresent) {
                if (!$Status) {
                    $Status = [pscustomobject]@{
                        PartitionKey       = 'Timer'
                        RowKey             = $Orchestrator.Id
                        Command            = $Orchestrator.Command
                        Cron               = $CronString
                        LastOccurrence     = 'Never'
                        NextOccurrence     = $NextOccurrence.ToUniversalTime()
                        Status             = 'Not Scheduled'
                        OrchestratorId     = ''
                        RunOnProcessor     = $RunOnProcessor
                        IsSystem           = $Orchestrator.IsSystem ?? $false
                        PreferredProcessor = $Orchestrator.PreferredProcessor ?? ''
                    }
                    Add-CIPPAzDataTableEntity @Table -Entity $Status -Force
                } else {
                    $Status.Command = $Orchestrator.Command
                    if ($Orchestrator.IsSystem -eq $true -or $ResetToDefault.IsPresent) {
                        $Status.Cron = $Orchestrator.Cron
                    }
                    $Status.NextOccurrence = $NextOccurrence.ToUniversalTime()
                    $PreferredProcessor = $Orchestrator.PreferredProcessor ?? ''
                    if ($Status.PSObject.Properites.Name -notcontains 'PreferredProcessor') {
                        $Status | Add-Member -MemberType NoteProperty -Name 'PreferredProcessor' -Value $PreferredProcessor -Force
                    } else {
                        $Status.PreferredProcessor = $PreferredProcessor
                    }
                    Add-CIPPAzDataTableEntity @Table -Entity $Status -Force
                }

                [PSCustomObject]@{
                    Id                 = $Orchestrator.Id
                    Priority           = $Orchestrator.Priority
                    Command            = $Orchestrator.Command
                    Parameters         = $Orchestrator.Parameters ?? @{}
                    Cron               = $CronString
                    NextOccurrence     = $NextOccurrence.ToUniversalTime()
                    LastOccurrence     = $Status.LastOccurrence
                    Status             = $Status.Status
                    OrchestratorId     = $Status.OrchestratorId
                    RunOnProcessor     = $Orchestrator.RunOnProcessor
                    IsSystem           = $Orchestrator.IsSystem ?? $false
                    PreferredProcessor = $Orchestrator.PreferredProcessor ?? ''
                    ErrorMsg           = $Status.ErrorMsg ?? ''
                }
            }
        } else {
            if ($Status) {
                Write-Warning "Timer function: $($Orchestrator.Command) does not exist"
                Remove-AzDataTableEntity @Table -Entity $Status
            }
        }
    }

    foreach ($StaleStatus in $OrchestratorStatus) {
        if ($Orchestrators.Id -notcontains $StaleStatus.RowKey) {
            Write-Warning "Removing stale timer function entry: $($StaleStatus.RowKey)"
            Remove-AzDataTableEntity @Table -Entity $StaleStatus
        }
    }
}
