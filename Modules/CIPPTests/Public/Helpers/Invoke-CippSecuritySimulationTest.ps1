function Invoke-CippSecuritySimulationTest {
    <#
    .SYNOPSIS
        Plays one Security Simulation scenario against a tenant and returns its test result row.
    .DESCRIPTION
        Shared body of every Invoke-CippTestSecuritySimulation_* test. The scenario comes from
        Tests/SecuritySimulations/scenarios.json. Standards are judged from the tenant's BaselineAlignment
        rows (a standard in no baseline is a gap that "Add to baseline" closes), alert steps from the alert
        rules the alert page writes, and the sign-in step live through the Conditional Access What If API
        as an account picked from the cache. The per-step detail lands in ResultDataJson for the Security
        Simulations page.
    .FUNCTIONALITY
        Internal
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$Tenant,
        [Parameter(Mandatory = $true)][string]$ScenarioId
    )

    $TestId = "SecuritySimulation_$ScenarioId"
    $Context = Get-CippSecuritySimulationContext -Tenant $Tenant -ScenarioId $ScenarioId
    $Scenario = $Context.Scenarios | Where-Object { $_.id -eq $ScenarioId } | Select-Object -First 1
    if (-not $Scenario) {
        return Add-CippTestResult -TenantFilter $Tenant -TestId $TestId -TestType 'Identity' -Status 'Skipped' -Name $ScenarioId -ResultMarkdown "Scenario '$ScenarioId' is not defined."
    }

    $Plan = $Context.Plans[$ScenarioId]
    $Licensed = $Plan.Licensed

    $AlertState = {
        param($Alert)
        if ($null -eq $Context.Rules) {
            $Rules = [System.Collections.Generic.List[object]]::new()
            $RuleTable = Get-CippTable -TableName 'WebhookRules'
            foreach ($Row in @(Get-CIPPAzDataTableEntity @RuleTable -Filter "PartitionKey eq 'Webhookv2'")) {
                if ($Row.Disabled -eq $true -or [string]::IsNullOrEmpty($Row.Tenants)) { continue }
                $Tenants = $(try { $Row.Tenants | ConvertFrom-Json -ErrorAction Stop } catch { $null })
                if ($null -eq $Tenants) { continue }
                $Expanded = @(Expand-CIPPTenantGroups -TenantFilter $Tenants)
                if (-not ($Expanded.value -contains $Tenant -or $Expanded.value -contains 'AllTenants')) { continue }
                $Excluded = $(try { $Row.excludedTenants | ConvertFrom-Json -ErrorAction Stop } catch { $null })
                if ($Excluded -and (@(Expand-CIPPTenantGroups -TenantFilter $Excluded).value -contains $Tenant)) { continue }
                $Operations = [System.Collections.Generic.List[string]]::new()
                $Properties = [System.Collections.Generic.List[string]]::new()
                foreach ($Condition in @($(try { $Row.Conditions | ConvertFrom-Json -ErrorAction Stop } catch { @() }) | Where-Object { $_ })) {
                    $Properties.Add("$($Condition.Property.label)")
                    if ("$($Condition.Property.label)" -ne 'Operation' -and "$($Condition.Property.value)" -ne 'List:Operation') { continue }
                    $Operator = "$($Condition.Operator.value)".ToLower()
                    if ($Operator -notin @('eq', 'in', 'like', 'contains', 'match')) { continue }
                    foreach ($ConditionInput in @($(if ($Condition.Input -is [array]) { $Condition.Input } else { @($Condition.Input) }))) {
                        $Value = "$($ConditionInput.value ?? $ConditionInput)"
                        if (-not $Value) { continue }
                        if ($Operator -eq 'contains') { $Value = "*$Value*" }
                        if (-not $Operations.Contains($Value)) { $Operations.Add($Value) }
                    }
                }
                $Rules.Add([PSCustomObject]@{ Logbook = "$($Row.type)"; Comment = "$($Row.AlertComment)"; Operations = @($Operations); Properties = @($Properties) })
            }
            $Context.Rules = $Rules
        }
        $Operation = "$($Alert.operation)"
        $Logbook = "$($Alert.logbook)"
        $Matched = @($Context.Rules | Where-Object {
                $Rule = $_
                if ($Logbook -and $Rule.Logbook -and $Rule.Logbook -ne $Logbook) { return $false }
                # A preset that narrows a broad operation (UserLoggedIn, Update user.) only counts when that condition is there too.
                if ($Alert.property -and @($Rule.Properties) -notcontains "$($Alert.property)") { return $false }
                @($Rule.Operations | Where-Object { $Operation -eq $_ -or $Operation -like $_ }).Count -gt 0
            })
        [PSCustomObject]@{
            operation  = $Operation
            logbook    = $Logbook
            preset     = "$($Alert.preset)"
            configured = $Matched.Count -gt 0
            rules      = @($Matched | ForEach-Object { if ($_.Comment) { $_.Comment } else { $_.Operations -join ', ' } })
        }
    }

    $Steps = @($Scenario.steps | Where-Object { $_ })
    $Persona = $Plan.Persona
    $CALicensed = $Plan.CALicensed
    $Identity = $Plan.Identity
    $AttackerCanSatisfy = @($Scenario.attackerCanSatisfy | Where-Object { $_ })

    $WhatIfCalls = 0
    $WhatIfSkipped = $false
    $Results = [System.Collections.Generic.List[object]]::new()
    $Reached = $true
    $ReachedWhenFixed = $true
    $PreventedAt = $null
    $PreventedWhenFixedAt = $null
    $Index = 0

    foreach ($Step in $Steps) {
        $Index++
        $StepId = "$($Step.id)"
        $Standards = @(foreach ($Reference in @($Step.standards | Where-Object { $_ })) {
                # Security defaults and per-user MFA cannot run alongside Conditional Access, so CA-licensed tenants skip them.
                if ($Reference.skipWhenLicensed -and (Test-CIPPStandardLicense -StandardName $TestId -TenantFilter $Tenant -Preset $Reference.skipWhenLicensed -SkipLog)) { continue }
                $State = $Context.Standards['{0}|{1}' -f $Reference.name, (ConvertTo-Json -Compress -Depth 5 -InputObject $Reference.secure)]
                [PSCustomObject]@{
                    name      = $State.name
                    label     = $State.label
                    role      = $(if ("$($Reference.role)") { "$($Reference.role)" } else { 'prevents' })
                    status    = $State.status
                    compliant = $State.compliant
                    assigned  = $State.assigned
                    detail    = $State.detail
                }
            })
        $Alerts = @(foreach ($Alert in @($Step.alerts | Where-Object { $_ })) { & $AlertState $Alert })

        $WhatIf = $null
        if ($Step.whatIf) {
            if (-not $CALicensed) {
                $WhatIf = [PSCustomObject]@{ verdict = 'unknown'; detail = 'unlicensed'; error = $(if ($Licensed) { 'This tenant is not licensed for Conditional Access (Entra ID P1 or P2).' } else { 'This tenant is not licensed for the capabilities this scenario needs.' }); gaps = @(); policies = @() }
                $WhatIfSkipped = $true
            } elseif (-not $Identity) {
                $WhatIf = [PSCustomObject]@{ verdict = 'unknown'; detail = 'noIdentity'; error = "No $Persona account is available in the cache to evaluate this sign-in."; gaps = @(); policies = @() }
                $WhatIfSkipped = $true
            } else {
                $WhatIfCalls++
                $Evaluation = $Context.WhatIf["$ScenarioId|$StepId"]
                if ($Evaluation.Error) {
                    $WhatIf = [PSCustomObject]@{ verdict = 'unknown'; detail = 'error'; error = "$($Evaluation.Error)"; gaps = @(); policies = @() }
                    $WhatIfSkipped = $true
                } else {
                    $Verdict = Get-CIPPCAWhatIfVerdict -Policies $Evaluation.Policies -AttackerCanSatisfy $AttackerCanSatisfy
                    $Gaps = foreach ($Gap in @($Step.gaps | Where-Object { $_ })) {
                        $GapLicensed = -not $Gap.licensePresets -or (Test-CIPPStandardLicense -StandardName $TestId -TenantFilter $Tenant -Preset $Gap.licensePresets -SkipLog)
                        $When = @($Gap.when | Where-Object { $_ } | ForEach-Object { "$_".ToLower() })
                        $Triggered = $GapLicensed -and (
                            ($When -contains 'allowed' -and $Verdict.verdict -eq 'allowed') -or
                            ($When -contains 'weakgrant' -and $Verdict.detail -eq 'grantSatisfied') -or
                            ($When -contains 'reportonly' -and @($Verdict.reportOnlyWouldStop).Count -gt 0)
                        )
                        [PSCustomObject]@{
                            text       = "$($Gap.text)"
                            role       = $(if ("$($Gap.role)") { "$($Gap.role)" } else { 'prevents' })
                            fix        = $Gap.fix
                            triggered  = [bool]$Triggered
                            unlicensed = -not $GapLicensed
                        }
                    }
                    $WhatIf = [PSCustomObject]@{
                        verdict             = $Verdict.verdict
                        detail              = $Verdict.detail
                        requiredControls    = @($Verdict.requiredControls)
                        blockedBy           = @($Verdict.blockedBy)
                        challengedBy        = @($Verdict.challengedBy)
                        reportOnlyWouldStop = @($Verdict.reportOnlyWouldStop)
                        policies            = @($Verdict.policies)
                        conditions          = $Step.whatIf
                        gaps                = @($Gaps)
                        error               = $null
                    }
                }
            }
        }

        $Checks = [System.Collections.Generic.List[bool]]::new()
        foreach ($Standard in $Standards) { if ($null -ne $Standard.compliant) { $Checks.Add([bool]$Standard.compliant) } }
        foreach ($Alert in $Alerts) { $Checks.Add([bool]$Alert.configured) }
        $Passed = @($Checks | Where-Object { $_ }).Count
        $HasChecks = $Standards.Count -gt 0 -or $Alerts.Count -gt 0
        $Kind = if ($WhatIf -and $HasChecks) { 'mixed' } elseif ($WhatIf) { 'whatIf' } elseif ($HasChecks) { 'checks' } else { 'narrative' }

        $StepVerdict = if ($WhatIf) { $WhatIf.verdict }
        elseif ($Checks.Count -eq 0) { $(if ($HasChecks) { 'unknown' } else { 'info' }) }
        elseif ($Passed -eq $Checks.Count) { 'pass' } elseif ($Passed -eq 0) { 'fail' } else { 'partial' }

        $VerdictLabel = switch ($StepVerdict) {
            'blocked' { $(if (@($WhatIf.blockedBy).Count -gt 0) { 'Blocked by policy' } else { 'Stopped - the attacker cannot satisfy the required controls' }) }
            'allowed' { $(if ($WhatIf.detail -eq 'grantSatisfied') { 'Allowed - the required controls are satisfied by the attacker' } else { 'Allowed - no enforced policy applies' }) }
            'pass' { 'Protected' }
            'partial' { 'Partly protected' }
            'fail' { 'Unprotected' }
            'unknown' { 'Could not be evaluated' }
            default { '' }
        }

        $TriggeredGaps = @($(if ($WhatIf) { $WhatIf.gaps | Where-Object { $_.triggered } }))
        $VerdictWhenFixed = if ($WhatIf) { $(if ($WhatIf.verdict -eq 'blocked' -or $TriggeredGaps.Count -gt 0) { 'blocked' } else { $WhatIf.verdict }) }
        elseif ($HasChecks) { 'pass' } else { 'info' }

        $Fixes = [System.Collections.Generic.List[object]]::new()
        foreach ($Standard in @($Standards | Where-Object { $_.compliant -eq $false })) {
            $Fixes.Add([PSCustomObject]@{ type = 'standard'; name = $Standard.name; label = $Standard.label; role = $Standard.role; status = $Standard.status; assigned = $Standard.assigned; step = $StepId })
        }
        foreach ($Gap in $TriggeredGaps) {
            $Fixes.Add([PSCustomObject]@{ type = 'caTemplate'; name = "$($Gap.fix.caTemplate)"; label = $Gap.text; role = $Gap.role; status = 'Missing'; assigned = $false; step = $StepId })
        }
        foreach ($Alert in @($Alerts | Where-Object { -not $_.configured })) {
            $Fixes.Add([PSCustomObject]@{
                    type      = 'alertPreset'
                    name      = $(if ($Alert.preset) { $Alert.preset } else { $Alert.operation })
                    label     = "Alert on $($Alert.operation)"
                    role      = 'detects'
                    status    = 'Not configured'
                    assigned  = $false
                    step      = $StepId
                    operation = $Alert.operation
                    logbook   = $Alert.logbook
                })
        }

        $Results.Add([PSCustomObject]@{
                id               = $StepId
                index            = $Index
                title            = "$($Step.title)"
                text             = "$($Step.text)"
                kind             = $Kind
                verdict          = $StepVerdict
                verdictLabel     = $VerdictLabel
                reached          = $Reached
                reachedWhenFixed = $ReachedWhenFixed
                verdictWhenFixed = $VerdictWhenFixed
                whenFixed        = $(if ("$($Step.whenFixed)") { "$($Step.whenFixed)" } else { $null })
                standards        = @($Standards)
                whatIf           = $WhatIf
                alerts           = @($Alerts)
                fixes            = @($Fixes)
            })

        # 'prevented' stops the chain when every gradable 'prevents' standard on the step is compliant.
        $StopsWhen = "$($Step.stopsChainWhen)".ToLower()
        $Preventing = @($Standards | Where-Object { $_.role -eq 'prevents' -and $null -ne $_.compliant })
        $Stops = if ($StopsWhen -eq 'prevented') { $Preventing.Count -gt 0 -and @($Preventing | Where-Object { -not $_.compliant }).Count -eq 0 } else { $StepVerdict -eq $StopsWhen }
        $StopsWhenFixed = if ($StopsWhen -eq 'prevented') { $Preventing.Count -gt 0 } else { $VerdictWhenFixed -eq $StopsWhen }
        if ($StopsWhen -and $Reached -and $Stops) { $Reached = $false; $PreventedAt = $StepId }
        if ($StopsWhen -and $ReachedWhenFixed -and $StopsWhenFixed) { $ReachedWhenFixed = $false; $PreventedWhenFixedAt = $StepId }
    }

    $UniqueFixes = [System.Collections.Generic.List[object]]::new()
    $Seen = [System.Collections.Generic.HashSet[string]]::new()
    foreach ($Fix in @($Results | ForEach-Object { $_.fixes })) {
        if ($Seen.Add("$($Fix.type)|$($Fix.name)")) { $UniqueFixes.Add($Fix) }
    }
    # An alert only fires when the unified audit log is ingesting.
    $AuditOn = @($Context.Standards.Keys | Where-Object { $_ -like 'AuditLog|*' } | ForEach-Object { $Context.Standards[$_].compliant }) -notcontains $false
    $DetectionOnly = @($Steps | Where-Object { $_.stopsChainWhen }).Count -eq 0
    $Detected = $AuditOn -and @($Results | Where-Object { $_.reached } | ForEach-Object { $_.alerts } | Where-Object { $_.configured }).Count -gt 0
    $Prevented = $null -ne $PreventedAt

    $Data = [PSCustomObject]@{
        scenario = [PSCustomObject]@{
            id       = "$($Scenario.id)"
            title    = "$($Scenario.title)"
            category = "$($Scenario.category)"
            severity = "$($Scenario.severity)"
            summary  = "$($Scenario.summary)"
            outcome  = $Scenario.outcome
        }
        licensed = [bool]$Licensed
        identity = $Identity
        lastRun  = [int64]([datetimeoffset]::UtcNow.ToUnixTimeSeconds())
        steps    = @($Results)
        summary  = [PSCustomObject]@{
            prevented                = $Prevented
            preventedAtStep          = $PreventedAt
            preventedWhenFixed       = $null -ne $PreventedWhenFixedAt
            preventedWhenFixedAtStep = $PreventedWhenFixedAt
            detected                 = [bool]$Detected
            detectionOnly            = $DetectionOnly
            fixCount                 = $UniqueFixes.Count
            fixes                    = @($UniqueFixes)
        }
        evidence = [PSCustomObject]@{ whatIfCalls = $WhatIfCalls }
    }

    # When no control can block the action, alerting on it is the protection there is.
    $Status = if (-not $Licensed) { 'Skipped' } elseif ($WhatIfSkipped) { 'Investigate' } elseif ($Prevented -or ($DetectionOnly -and $Detected)) { 'Passed' } else { 'Failed' }
    $Headline = if (-not $Licensed) { 'Not evaluated: the tenant is not licensed for the capabilities this scenario needs.' }
    elseif ($WhatIfSkipped) { 'The sign-in step could not be evaluated, so the outcome is unknown.' }
    elseif ($Prevented) { "Prevented. $($Scenario.outcome.prevented)" }
    elseif ($DetectionOnly -and $Detected) { 'Detected. No control can block this action, and an alert fires when it happens.' }
    elseif ($Detected) { "Not prevented, but an alert would fire. $($Scenario.outcome.notPrevented)" }
    else { "Not prevented and undetected. $($Scenario.outcome.notPrevented)" }
    $FixLine = if ($UniqueFixes.Count -gt 0) { "`n`nCloses the gaps: " + (@($UniqueFixes | ForEach-Object { if ($_.type -eq 'caTemplate') { $_.name } else { $_.label } }) -join '; ') + '.' } else { '' }

    Add-CippTestResult -TenantFilter $Tenant -TestId $TestId -TestType 'Identity' -Status $Status `
        -Name "$($Scenario.title)" -Risk "$($Scenario.severity)" -Category "$($Scenario.category)" `
        -ResultMarkdown ("$Headline$FixLine") -ResultDataJson (ConvertTo-Json -InputObject $Data -Depth 20 -Compress)
}
