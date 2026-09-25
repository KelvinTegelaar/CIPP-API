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
    $Path = Join-Path $env:CIPPRootPath 'Modules\CIPPTests\Public\Tests\SecuritySimulations\scenarios.json'
    $Scenario = @([System.IO.File]::ReadAllText($Path) | ConvertFrom-Json -Depth 20) | Where-Object { $_.id -eq $ScenarioId } | Select-Object -First 1
    if (-not $Scenario) {
        return Add-CippTestResult -TenantFilter $Tenant -TestId $TestId -TestType 'Identity' -Status 'Skipped' -Name $ScenarioId -ResultMarkdown "Scenario '$ScenarioId' is not defined."
    }

    $Capabilities = $(try { Get-CIPPTenantCapabilities -TenantFilter $Tenant } catch { $null })
    $IsLicensed = {
        param($Required)
        $Needed = @($Required | Where-Object { $_ })
        $Needed.Count -eq 0 -or @($Needed | Where-Object { $Capabilities.$_ -eq $true }).Count -gt 0
    }
    $Licensed = & $IsLicensed $Scenario.requiredCapabilities

    $AlignmentTable = Get-CippTable -tablename 'BaselineAlignment'
    $SafeTenant = ConvertTo-CIPPODataFilterValue -Value $Tenant
    $AlignmentRows = @(Get-CIPPAzDataTableEntity @AlignmentTable -Filter "PartitionKey eq '$SafeTenant'")

    $StandardState = {
        param($Reference)
        $Name = "$($Reference.name)"
        $Definition = Get-CIPPBaselineDefinition -Name $Name | Select-Object -First 1
        $State = [PSCustomObject]@{
            name      = $Name
            label     = "$($Definition.label ?? $Name)"
            role      = $(if ("$($Reference.role)") { "$($Reference.role)" } else { 'prevents' })
            status    = 'Not in a baseline'
            compliant = $false
            assigned  = $false
            detail    = ''
        }
        $Row = @($AlignmentRows | Where-Object { ("$($_.StandardName)" -split '#')[0] -eq $Name }) |
            Sort-Object -Property { [int64]($_.LastRun ?? 0) } -Descending | Select-Object -First 1
        if ($Row) {
            $State.assigned = $true
            switch -Regex ("$($Row.Status)") {
                '^Compliant$' { $State.status = 'Compliant'; $State.compliant = $true }
                '^(Accepted|Partially Accepted)$' { $State.status = 'Accepted deviation'; $State.compliant = $false; $State.detail = "$($Row.DeviationReason)" }
                '^(Denied|Drift)' { $State.status = 'Drift'; $State.compliant = $false }
                '^Skipped - No License$' { $State.status = 'License missing'; $State.compliant = $null }
                default { $State.status = 'No data'; $State.compliant = $null }
            }
        } elseif (-not (& $IsLicensed $Definition.requiredCapabilities)) {
            $State.status = 'License missing'
            $State.compliant = $null
        } else {
            try {
                $Item = @{
                    TenantFilter     = $Tenant
                    TenantName       = $Tenant
                    Standard         = $Name
                    BaseName         = $Name
                    Variables        = $null
                    Tiers            = @()
                    Stage            = 1
                    StageName        = ''
                    TemplateId       = ''
                    SourceScope      = 'test'
                    SourceTemplate   = 'Security Simulation'
                    RemediateEnabled = $false
                    AlertEnabled     = $false
                }
                $Graded = Invoke-CIPPBaselineStandard -Item $Item -Mode 'compare' -GradeOnly
                if ($null -eq $Graded) {
                    $State.status = 'Needs configuration'
                    $State.detail = 'This standard needs its settings chosen in a baseline before it can be checked.'
                } elseif ($Graded.Compliant -eq $true) {
                    $State.status = 'Compliant'
                    $State.compliant = $true
                } else {
                    $State.status = 'Not configured'
                    $Properties = @($Graded.Diff | ForEach-Object { $_.Property } | Where-Object { $_ } | Select-Object -Unique)
                    if ($Properties.Count -gt 0) { $State.detail = 'Differs on: {0}' -f ($Properties -join ', ') }
                }
            } catch {
                $State.status = 'Could not evaluate'
                $State.compliant = $null
                $State.detail = $_.Exception.Message
            }
        }
        $State
    }

    $Rules = $null
    $AlertState = {
        param($Alert)
        if ($null -eq $Rules) {
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
                foreach ($Condition in @($(try { $Row.Conditions | ConvertFrom-Json -ErrorAction Stop } catch { @() }) | Where-Object { $_ })) {
                    if ("$($Condition.Property.label)" -ne 'Operation' -and "$($Condition.Property.value)" -ne 'List:Operation') { continue }
                    $Operator = "$($Condition.Operator.value)".ToLower()
                    if ($Operator -notin @('eq', 'in', 'like', 'contains', 'match')) { continue }
                    foreach ($Input in @($(if ($Condition.Input -is [array]) { $Condition.Input } else { @($Condition.Input) }))) {
                        $Value = "$($Input.value ?? $Input)"
                        if (-not $Value) { continue }
                        if ($Operator -eq 'contains') { $Value = "*$Value*" }
                        if (-not $Operations.Contains($Value)) { $Operations.Add($Value) }
                    }
                }
                $Rules.Add([PSCustomObject]@{ Logbook = "$($Row.type)"; Comment = "$($Row.AlertComment)"; Operations = @($Operations) })
            }
        }
        $Operation = "$($Alert.operation)"
        $Logbook = "$($Alert.logbook)"
        $Matched = @($Rules | Where-Object {
                $Rule = $_
                if ($Logbook -and $Rule.Logbook -and $Rule.Logbook -ne $Logbook) { return $false }
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
    $Persona = $(if ("$($Scenario.persona)") { "$($Scenario.persona)" } else { 'user' })
    $NeedsIdentity = @($Steps | Where-Object { $_.whatIf }).Count -gt 0
    $Identity = $(if ($NeedsIdentity -and $Licensed) { Resolve-CIPPSimulationIdentity -TenantFilter $Tenant -Persona $Persona } else { $null })
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
        $Standards = @(foreach ($Reference in @($Step.standards | Where-Object { $_ })) { & $StandardState $Reference })
        $Alerts = @(foreach ($Alert in @($Step.alerts | Where-Object { $_ })) { & $AlertState $Alert })

        $WhatIf = $null
        if ($Step.whatIf) {
            if (-not $Licensed) {
                $WhatIf = [PSCustomObject]@{ verdict = 'unknown'; detail = 'unlicensed'; error = 'This tenant is not licensed for Conditional Access.'; gaps = @(); policies = @() }
                $WhatIfSkipped = $true
            } elseif (-not $Identity) {
                $WhatIf = [PSCustomObject]@{ verdict = 'unknown'; detail = 'noIdentity'; error = "No $Persona account is available in the cache to evaluate this sign-in."; gaps = @(); policies = @() }
                $WhatIfSkipped = $true
            } else {
                $Body = New-CIPPCAWhatIfRequest -UserId $Identity.userId -IncludeApplications $Step.whatIf.includeApplications -Conditions ($Step.whatIf | Select-Object -Property * -ExcludeProperty includeApplications)
                $WhatIfCalls++
                $Evaluation = @(Invoke-CIPPCAWhatIf -TenantFilter $Tenant -Bodies @($Body))[0]
                if ($Evaluation.Error) {
                    $WhatIf = [PSCustomObject]@{ verdict = 'unknown'; detail = 'error'; error = "$($Evaluation.Error)"; gaps = @(); policies = @() }
                    $WhatIfSkipped = $true
                } else {
                    $Verdict = Get-CIPPCAWhatIfVerdict -Policies $Evaluation.Policies -AttackerCanSatisfy $AttackerCanSatisfy
                    $Gaps = foreach ($Gap in @($Step.gaps | Where-Object { $_ })) {
                        $GapLicensed = & $IsLicensed $Gap.requiredCapabilities
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

        $StopsWhen = "$($Step.stopsChainWhen)".ToLower()
        if ($StopsWhen -and $Reached -and $StepVerdict -eq $StopsWhen) { $Reached = $false; $PreventedAt = $StepId }
        if ($StopsWhen -and $ReachedWhenFixed -and $VerdictWhenFixed -eq $StopsWhen) { $ReachedWhenFixed = $false; $PreventedWhenFixedAt = $StepId }
    }

    $UniqueFixes = [System.Collections.Generic.List[object]]::new()
    $Seen = [System.Collections.Generic.HashSet[string]]::new()
    foreach ($Fix in @($Results | ForEach-Object { $_.fixes })) {
        if ($Seen.Add("$($Fix.type)|$($Fix.name)")) { $UniqueFixes.Add($Fix) }
    }
    $Detected = @($Results | Where-Object { $_.reached } | ForEach-Object { $_.alerts } | Where-Object { $_.configured }).Count -gt 0
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
            fixCount                 = $UniqueFixes.Count
            fixes                    = @($UniqueFixes)
        }
        evidence = [PSCustomObject]@{ whatIfCalls = $WhatIfCalls }
    }

    $Status = if (-not $Licensed) { 'Skipped' } elseif ($WhatIfSkipped) { 'Investigate' } elseif ($Prevented) { 'Passed' } else { 'Failed' }
    $Headline = if (-not $Licensed) { 'Not evaluated: the tenant is not licensed for the capabilities this scenario needs.' }
    elseif ($WhatIfSkipped) { 'The sign-in step could not be evaluated, so the outcome is unknown.' }
    elseif ($Prevented) { "Prevented. $($Scenario.outcome.prevented)" }
    elseif ($Detected) { "Not prevented, but an alert would fire. $($Scenario.outcome.notPrevented)" }
    else { "Not prevented and undetected. $($Scenario.outcome.notPrevented)" }
    $FixLine = if ($UniqueFixes.Count -gt 0) { "`n`nCloses the gaps: " + (@($UniqueFixes | ForEach-Object { if ($_.type -eq 'caTemplate') { $_.name } else { $_.label } }) -join '; ') + '.' } else { '' }

    Add-CippTestResult -TenantFilter $Tenant -TestId $TestId -TestType 'Identity' -Status $Status `
        -Name "$($Scenario.title)" -Risk "$($Scenario.severity)" -Category "$($Scenario.category)" `
        -ResultMarkdown ("$Headline$FixLine") -ResultDataJson (ConvertTo-Json -InputObject $Data -Depth 20 -Compress)
}
