function Invoke-CIPPBaselineGraduation {
    <#
    .SYNOPSIS
        Advances tenants through baseline stages whose graduation conditions are met.
    .DESCRIPTION
        Runs at the start of every scheduled baseline run. For each tenant not yet in a
        baseline's final stage, the NEXT stage's conditions are evaluated with the stage's
        AND/OR logic:
        - time:     enteredStageAt + days/weeks has elapsed (unix seconds)
        - variable: a per-tenant custom variable (Get-CIPPTextReplacement's replacement map)
                    compared with eq/ne/startsWith/notStartsWith
        - success:  every standard rolled out by the stages reached so far is aligned
                    (Compliant or Accepted) on the tenant's resolved rows
        - manual:   never auto-advances (operator uses ExecBaselineStage)
        A stage with no conditions does not auto-advance.
    .FUNCTIONALITY
        Internal
    #>
    [CmdletBinding()]
    param()

    $Now = [int64]([datetimeoffset]::UtcNow.ToUnixTimeSeconds())
    $StateTable = Get-CippTable -tablename 'BaselineRolloutState'
    $ResolvedTable = Get-CippTable -tablename 'BaselineAlignment'
    $Definitions = @(Get-CIPPBaselineDefinition)

    foreach ($Baseline in @(Get-CIPPBaseline)) {
        foreach ($State in $Baseline.tenantStates) {
            if ($State.currentStage -ge $State.totalStages) { continue }
            $NextStage = $Baseline.stages[$State.currentStage]
            $Conditions = @($NextStage.conditions)
            if ($Conditions.Count -eq 0) { continue }

            $Results = foreach ($Condition in $Conditions) {
                switch ($Condition.type) {
                    'time' {
                        $Multiplier = if ($Condition.unit -eq 'weeks') { 7 } else { 1 }
                        $EnteredAt = [int64]($State.enteredStageAt ?? 0)
                        $EnteredAt -gt 0 -and $Now -ge ($EnteredAt + ([int64]$Condition.days * $Multiplier * 86400))
                    }
                    'variable' {
                        # Reuse the replacement machinery: an unresolved token comes back verbatim.
                        $Token = '%{0}%' -f $Condition.variable
                        $Value = Get-CIPPTextReplacement -TenantFilter $State.tenantFilter -Text $Token
                        if ($Value -eq $Token) { $false } else {
                            switch ($Condition.operator) {
                                'ne' { $Value -ne $Condition.value }
                                'startsWith' { "$Value".StartsWith("$($Condition.value)") }
                                'notStartsWith' { -not "$Value".StartsWith("$($Condition.value)") }
                                default { $Value -eq $Condition.value }
                            }
                        }
                    }
                    'success' {
                        # Package standards never resolve under their own key - expand
                        # them so success means EVERY MEMBER template aligned, using the
                        # same derived instance keys the resolver writes rows under.
                        $RolledOut = [System.Collections.Generic.List[string]]::new()
                        foreach ($StageDef in @($Baseline.stages | Select-Object -First $State.currentStage)) {
                            foreach ($Config in @($StageDef.standardsConfig)) {
                                if (-not $Config) { continue }
                                $BaseName = ("$($Config.instance ?? $Config.standard)" -split '#')[0]
                                $Definition = $Definitions | Where-Object { $_.name -eq $BaseName } | Select-Object -First 1
                                if ($Definition.package) {
                                    foreach ($Member in @(Expand-CIPPBaselineTemplatePackage -Definition $Definition -Config $Config)) { $RolledOut.Add("$($Member.instance)") }
                                } else {
                                    $RolledOut.Add("$($Config.instance)")
                                }
                            }
                        }
                        $RolledOut = @($RolledOut | Select-Object -Unique)
                        $SafeTenant = ConvertTo-CIPPODataFilterValue -Value $State.tenantFilter
                        $Rows = @(Get-CIPPAzDataTableEntity @ResolvedTable -Filter "PartitionKey eq '$SafeTenant'")
                        $Aligned = 0
                        foreach ($Standard in $RolledOut) {
                            $Row = $Rows | Where-Object { $_.StandardName -eq $Standard } | Select-Object -First 1
                            if ($Row -and $Row.Status -in @('Compliant', 'Accepted')) { $Aligned++ }
                        }
                        $RolledOut.Count -gt 0 -and $Aligned -eq $RolledOut.Count
                    }
                    default { $false } # manual and anything unknown never auto-advance
                }
            }

            $Advance = if ($NextStage.logic -eq 'or') { $Results -contains $true } else { $Results -notcontains $false }
            if (-not $Advance) { continue }

            $StateTable.Force = $true
            Add-CIPPAzDataTableEntity @StateTable -Entity @{
                PartitionKey    = "$($Baseline.GUID)"
                RowKey          = "$($State.tenantFilter)"
                currentStage    = ($State.currentStage + 1)
                enteredStageAt  = $Now
                firstDeployedAt = $State.firstDeployedAt ?? $State.enteredStageAt ?? $Now
            }
            $null = Add-CIPPBaselineHistoryEvent -TenantFilter $State.tenantFilter -Standard $Baseline.templateName -Mode 'stage' -TriggeredBy 'schedule' -Outcome 'Stage Advanced' -Detail "Graduated to stage $($State.currentStage + 1) ($($NextStage.name)) - the stage's conditions were met"
            Write-LogMessage -API 'Baselines' -tenant $State.tenantFilter -message "Graduated $($State.tenantFilter) to stage $($State.currentStage + 1) ($($NextStage.name)) of baseline $($Baseline.templateName)." -Sev 'Info'
        }
    }
}
