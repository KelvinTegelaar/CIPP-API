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
        - group:    the tenant is a member of the selected tenant group, evaluated fresh
                    on every run - an 'All Tenants' baseline can gate a stage (say Intune
                    policies) on an 'Intune licensed' group
        - success:  every standard rolled out by the stages reached so far is aligned
                    (Compliant or Accepted) on the tenant's resolved rows; a standard the
                    tenant cannot license counts as aligned rather than blocking the stage
        - manual:   never auto-advances (operator uses ExecBaselineStage)
        A stage with no conditions does not auto-advance.
        -TenantFilter/-TemplateId scope an on-demand re-evaluation; one result is emitted per
        evaluated tenant state.
    .FUNCTIONALITY
        Internal
    #>
    [CmdletBinding()]
    param(
        [string]$TenantFilter,
        [string]$TemplateId,
        [string]$TriggeredBy = 'schedule'
    )

    $Now = [int64]([datetimeoffset]::UtcNow.ToUnixTimeSeconds())
    $StateTable = Get-CippTable -tablename 'BaselineRolloutState'
    $ResolvedTable = Get-CippTable -tablename 'BaselineAlignment'
    $Definitions = @(Get-CIPPBaselineDefinition)
    $Groups = @()
    try { $Groups = @(Get-TenantGroups -SkipCache) } catch { Write-Information "Invoke-CIPPBaselineGraduation: tenant group lookup failed: $($_.Exception.Message)" }

    $Baselines = if ($TemplateId) { @(Get-CIPPBaseline -ID $TemplateId) } else { @(Get-CIPPBaseline) }
    foreach ($Baseline in $Baselines) {
        foreach ($State in $Baseline.tenantStates) {
            if ($TenantFilter -and $State.tenantFilter -ne $TenantFilter) { continue }
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
                    'group' {
                        # Membership gate: only tenants in the selected group ever advance.
                        # Accepts the stored group ID or a hand-authored name, the same way
                        # scope resolution does. Missing group/empty selection never advances.
                        $GroupKey = "$($Condition.group.value ?? $Condition.group)"
                        $Group = $Groups | Where-Object { $_.Id -eq $GroupKey -or $_.Name -eq $GroupKey } | Select-Object -First 1
                        @($Group.Members.defaultDomainName) -contains $State.tenantFilter
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
                            # A standard the tenant cannot license is not drift it can fix, and the engine
                            # rewrites that status every run so it cannot be accepted away either.
                            if ($Row -and $Row.Status -in @('Compliant', 'Accepted', 'Skipped - No License')) { $Aligned++ }
                        }
                        $RolledOut.Count -gt 0 -and $Aligned -eq $RolledOut.Count
                    }
                    default { $false } # manual and anything unknown never auto-advance
                }
            }

            $Results = @($Results)
            $Advance = if ($NextStage.logic -eq 'or') { $Results -contains $true } else { $Results -notcontains $false }
            [pscustomobject]@{
                TenantFilter = $State.tenantFilter
                Advanced     = [bool]$Advance
                Stage        = if ($Advance) { $State.currentStage + 1 } else { $State.currentStage }
                StageName    = if ($Advance) { $NextStage.name } else { $State.stageName }
                Unmet        = @(for ($i = 0; $i -lt $Conditions.Count; $i++) { if (-not $Results[$i]) { $Conditions[$i].type } })
            }
            if (-not $Advance) { continue }

            $StateTable.Force = $true
            Add-CIPPAzDataTableEntity @StateTable -Entity @{
                PartitionKey    = "$($Baseline.GUID)"
                RowKey          = "$($State.tenantFilter)"
                currentStage    = ($State.currentStage + 1)
                enteredStageAt  = $Now
                firstDeployedAt = $State.firstDeployedAt ?? $State.enteredStageAt ?? $Now
            }
            $null = Add-CIPPBaselineHistoryEvent -TenantFilter $State.tenantFilter -Standard $Baseline.templateName -Mode 'stage' -TriggeredBy $TriggeredBy -Outcome 'Stage Advanced' -Detail "Graduated to stage $($State.currentStage + 1) ($($NextStage.name)) - the stage's conditions were met"
            Write-LogMessage -API 'Baselines' -tenant $State.tenantFilter -message "Graduated $($State.tenantFilter) to stage $($State.currentStage + 1) ($($NextStage.name)) of baseline $($Baseline.templateName)." -Sev 'Info'
        }
    }
}
