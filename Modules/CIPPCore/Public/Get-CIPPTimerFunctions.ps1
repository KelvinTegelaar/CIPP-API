function Get-CIPPTimerFunctions {
    [CmdletBinding()]
    param(
        [switch]$All,
        [switch]$ResetToDefault
    )

    $ConfigTable = Get-CIPPTable -tablename Config
    $Config = Get-CIPPAzDataTableEntity @ConfigTable -Filter "PartitionKey eq 'OffloadFunctions' and RowKey eq 'OffloadFunctions'"

    # Check running nodes
    $VersionTable = Get-CIPPTable -tablename 'Version'
    $Nodes = Get-CIPPAzDataTableEntity @VersionTable -Filter "PartitionKey eq 'Version' and RowKey ne 'Version'" | Where-Object { $_.RowKey -match '-' }
    $AvailableNodes = $Nodes.RowKey | ForEach-Object { ($_ -split '-')[1] }
    $FunctionName = $env:WEBSITE_SITE_NAME

    # Get node name
    if ($FunctionName -match '-') {
        $Node = ($FunctionName -split '-')[1]
    } else {
        $Node = 'http'
    }

    $RunOnProcessor = $true
    if ($Config -and $Config.state -eq $true) {
        if ($env:CIPP_PROCESSOR -ne 'true' -and !$All.IsPresent) {
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
    $Orchestrators = Get-Content -Path $CIPPRoot\CIPPTimers.json | ConvertFrom-Json | Where-Object { $_.RunOnProcessor -eq $RunOnProcessor }
    $Table = Get-CIPPTable -TableName 'CIPPTimers'
    $RunOnProcessorTxt = if ($RunOnProcessor) { 'true' } else { 'false' }
    $OrchestratorStatus = Get-CIPPAzDataTableEntity @Table -Filter "RunOnProcessor eq $RunOnProcessorTxt"
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

        if ($Orchestrator.PreferredProcessor -and $AvailableNodes -contains $Orchestrator.PreferredProcessor -and $Node -ne $Orchestrator.PreferredProcessor) {
            # only run on preferred processor when available
            continue
        } elseif ((!$Orchestrator.PreferredProcessor -or $AvailableNodes -notcontains $Orchestrator.PreferredProcessor) -and $Node -notin ('http', 'proc')) {
            # Catchall function nodes
            continue
        }

        $Now = Get-Date
        if ($All.IsPresent) {
            $NextOccurrence = [datetime]$Cron.GetNextOccurrence($Now)
        } else {
            $NextOccurrences = $Cron.GetNextOccurrences($Now.AddMinutes(-15), $Now.AddMinutes(15))
            if (!$Status -or $Status.LastOccurrence -eq 'Never') {
                $NextOccurrence = $NextOccurrences | Where-Object { $_ -le (Get-Date) } | Select-Object -First 1
            } else {
                $NextOccurrence = $NextOccurrences | Where-Object { $_ -gt $Status.LastOccurrence.DateTime.ToLocalTime() -and $_ -le (Get-Date) } | Select-Object -First 1
            }
        }

        if (Get-Command -Name $Orchestrator.Command -Module CIPPCore -ErrorAction SilentlyContinue) {
            if ($NextOccurrence) {
                if (!$Status) {
                    $Status = [pscustomobject]@{
                        PartitionKey       = 'Timer'
                        RowKey             = $Orchestrator.Command
                        Cron               = $CronString
                        LastOccurrence     = 'Never'
                        NextOccurrence     = $NextOccurrence.ToUniversalTime()
                        Status             = 'Not Scheduled'
                        OrchestratorId     = ''
                        RunOnProcessor     = $RunOnProcessor
                        IsSystem           = $Orchestrator.IsSystem ?? $false
                        PreferredProcessor = $Orchestrator.PreferredProcessor ?? ''
                    }
                    Add-CIPPAzDataTableEntity @Table -Entity $Status
                } else {
                    if ($Orchestrator.IsSystem -eq $true -or $ResetToDefault.IsPresent) {
                        $Status.Cron = $CronString
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
                    Command            = $Orchestrator.Command
                    Cron               = $CronString
                    NextOccurrence     = $NextOccurrence.ToUniversalTime()
                    LastOccurrence     = $Status.LastOccurrence.DateTime
                    Status             = $Status.Status
                    OrchestratorId     = $Status.OrchestratorId
                    RunOnProcessor     = $Orchestrator.RunOnProcessor
                    IsSystem           = $Orchestrator.IsSystem ?? $false
                    PreferredProcessor = $Orchestrator.PreferredProcessor ?? ''
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
