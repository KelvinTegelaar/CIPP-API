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
                        $RolledOut = @($Baseline.stages | Select-Object -First $State.currentStage |
                                ForEach-Object { @($_.standards) } | Select-Object -Unique)
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
            Write-LogMessage -API 'Baselines' -tenant $State.tenantFilter -message "Graduated $($State.tenantFilter) to stage $($State.currentStage + 1) ($($NextStage.name)) of baseline $($Baseline.templateName)." -Sev 'Info'
        }
    }
}
