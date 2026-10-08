function Get-CippSecuritySimulationContext {
    <#
    .SYNOPSIS
        Everything the Security Simulation tests read for a tenant, fetched once.
    .DESCRIPTION
        Loads the scenarios, picks the account each persona signs in as, evaluates every What If step in one
        batch and grades each standard once against the secure value its scenario defines. During a suite run Initialize-CippTestSuiteSecuritySimulations
        shares one context across all scenario tests; a single test builds one for its own scenario.
    .FUNCTIONALITY
        Internal
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$Tenant,
        [string]$ScenarioId
    )

    if ($script:CippSecuritySimulationContext.Tenant -eq $Tenant) { return $script:CippSecuritySimulationContext }

    $Path = Join-Path $env:CIPPRootPath 'Modules\CIPPTests\Public\Tests\SecuritySimulations\scenarios.json'
    $Scenarios = @([System.IO.File]::ReadAllText($Path) | ConvertFrom-Json -Depth 20 | Where-Object { -not $ScenarioId -or $_.id -eq $ScenarioId })
    $AlignmentTable = Get-CippTable -tablename 'BaselineAlignment'
    $SafeTenant = ConvertTo-CIPPODataFilterValue -Value $Tenant
    $AlignmentRows = @(Get-CIPPAzDataTableEntity @AlignmentTable -Filter "PartitionKey eq '$SafeTenant'")
    $Context = @{
        Tenant    = $Tenant
        Scenarios = $Scenarios
        Plans     = @{}
        WhatIf    = @{}
        Standards = @{}
        Timings   = [System.Collections.Generic.List[object]]::new()
        Rules     = $null
    }

    $Directory = $null
    $Identities = @{}
    $WhatIfKeys = [System.Collections.Generic.List[string]]::new()
    $WhatIfBodies = [System.Collections.Generic.List[object]]::new()
    foreach ($Scenario in $Scenarios) {
        $TestId = "SecuritySimulation_$($Scenario.id)"
        $Licensed = -not $Scenario.licensePresets -or (Test-CIPPStandardLicense -StandardName $TestId -TenantFilter $Tenant -Preset $Scenario.licensePresets -SkipLog)
        $Persona = $(if ("$($Scenario.persona)") { "$($Scenario.persona)" } else { 'user' })
        $WhatIfSteps = @($Scenario.steps | Where-Object { $_.whatIf })
        # The What If API itself needs Entra ID P1 or P2, whatever else the scenario is licensed for.
        $CALicensed = $WhatIfSteps.Count -gt 0 -and $Licensed -and (Test-CIPPStandardLicense -StandardName $TestId -TenantFilter $Tenant -Preset Entra -SkipLog)
        $Identity = $null
        if ($CALicensed) {
            if (-not $Identities.ContainsKey($Persona)) {
                $Directory ??= @{
                    Users    = @(Get-CIPPSimulationCache -TenantFilter $Tenant -Type 'Users')
                    Roles    = @(Get-CIPPSimulationCache -TenantFilter $Tenant -Type 'Roles')
                    Policies = @(Get-CIPPSimulationCache -TenantFilter $Tenant -Type 'ConditionalAccessPolicies')
                }
                $Identities[$Persona] = Resolve-CIPPSimulationIdentity -TenantFilter $Tenant -Persona $Persona -Users $Directory.Users -Roles $Directory.Roles -Policies $Directory.Policies
            }
            $Identity = $Identities[$Persona]
        }
        if ($Identity) {
            foreach ($Step in $WhatIfSteps) {
                $WhatIfKeys.Add("$($Scenario.id)|$($Step.id)")
                $WhatIfBodies.Add((New-CIPPCAWhatIfRequest -UserId $Identity.userId -IncludeApplications $Step.whatIf.includeApplications -Conditions ($Step.whatIf | Select-Object -Property * -ExcludeProperty includeApplications)))
            }
        }
        $Context.Plans["$($Scenario.id)"] = [PSCustomObject]@{ Licensed = [bool]$Licensed; CALicensed = [bool]$CALicensed; Persona = $Persona; Identity = $Identity }
    }

    if ($WhatIfBodies.Count -gt 0) {
        $Evaluations = @(Invoke-CIPPCAWhatIf -TenantFilter $Tenant -Bodies @($WhatIfBodies))
        for ($i = 0; $i -lt $WhatIfKeys.Count; $i++) { $Context.WhatIf[$WhatIfKeys[$i]] = $Evaluations[$i] }
    }

    # Graded live against the scenario's secure value (a list means any entry is secure); tenant-specific settings use the baseline verdict.
    $References = @($Scenarios.steps.standards | Where-Object { $_ })
    foreach ($Reference in $References) {
        $Name = "$($Reference.name)"
        $Key = '{0}|{1}' -f $Name, (ConvertTo-Json -Compress -Depth 5 -InputObject $Reference.secure)
        if ($Context.Standards.ContainsKey($Key)) { continue }
        $Stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
        $Definition = Get-CIPPBaselineDefinition -Name $Name | Select-Object -First 1
        $State = [PSCustomObject]@{
            name      = $Name
            label     = "$($Definition.label ?? $Name)"
            status    = 'Not configured'
            compliant = $false
            assigned  = $false
            detail    = ''
        }
        $Row = @($AlignmentRows | Where-Object { ("$($_.StandardName)" -split '#')[0] -eq $Name }) |
            Sort-Object -Property { [int64]($_.LastRun ?? 0) } -Descending | Select-Object -First 1
        $State.assigned = $null -ne $Row
        $TenantSpecific = @(($Definition.variables ?? [PSCustomObject]@{}).PSObject.Properties | Where-Object {
                $_.Value.required -eq $true -and $null -eq ($_.Value.default ?? $_.Value.recommended) -and -not ($Reference.secure -and $Reference.secure.PSObject.Properties[$_.Name])
            }).Count -gt 0

        if ($Definition.requiredCapabilities -and -not (Test-CIPPStandardLicense -StandardName $Name -TenantFilter $Tenant -RequiredCapabilities @($Definition.requiredCapabilities | ForEach-Object { $_ }) -SkipLog)) {
            $State.status = 'License missing'
            $State.compliant = $null
        } elseif ($TenantSpecific) {
            switch -Regex ("$($Row.Status)") {
                '^Compliant$' { $State.status = 'Compliant'; $State.compliant = $true }
                '^(Accepted|Partially Accepted)$' { $State.status = 'Accepted deviation'; $State.detail = "$($Row.DeviationReason)" }
                '^(Denied|Drift)' { $State.status = 'Drift' }
                '^Skipped - No License$' { $State.status = 'License missing'; $State.compliant = $null }
                '^$' { $State.status = 'Needs configuration'; $State.detail = 'This standard needs tenant-specific settings, chosen in a baseline, before it can be checked.' }
                default { $State.status = 'No data'; $State.compliant = $null }
            }
        } else {
            $Candidates = [System.Collections.Generic.List[object]]::new()
            $Candidates.Add([ordered]@{})
            foreach ($Setting in @(if ($Reference.secure) { $Reference.secure.PSObject.Properties })) {
                $Expanded = [System.Collections.Generic.List[object]]::new()
                foreach ($Candidate in $Candidates) {
                    foreach ($Value in @($Setting.Value)) {
                        $Next = [ordered]@{}
                        foreach ($Existing in $Candidate.Keys) { $Next[$Existing] = $Candidate[$Existing] }
                        $Next[$Setting.Name] = $Value
                        $Expanded.Add($Next)
                    }
                }
                $Candidates = $Expanded
            }
            try {
                $FirstDiff = $null
                foreach ($Candidate in $Candidates) {
                    $Item = @{
                        TenantFilter     = $Tenant
                        TenantName       = $Tenant
                        Standard         = $Name
                        BaseName         = $Name
                        Variables        = $(if ($Candidate.Count -gt 0) { [PSCustomObject]$Candidate } else { $null })
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
                        break
                    }
                    if ($Graded.Compliant -eq $true) {
                        $State.status = 'Compliant'
                        $State.compliant = $true
                        break
                    }
                    $FirstDiff ??= @($Graded.Diff | ForEach-Object { $_.Property } | Where-Object { $_ } | Select-Object -Unique)
                }
                if ($State.compliant -eq $false -and $State.status -eq 'Not configured') {
                    if ("$($Row.Status)" -match '^(Accepted|Partially Accepted)$') {
                        $State.status = 'Accepted deviation'
                        $State.detail = "$($Row.DeviationReason)"
                    } elseif (@($FirstDiff).Count -gt 0) {
                        $State.detail = 'Differs on: {0}' -f ($FirstDiff -join ', ')
                    }
                }
            } catch {
                $State.status = 'Could not evaluate'
                $State.compliant = $null
                $State.detail = $_.Exception.Message
            }
        }
        $Context.Standards[$Key] = $State
        $Context.Timings.Add([PSCustomObject]@{ Name = $Name; Seconds = $Stopwatch.Elapsed.TotalSeconds })
    }
    $Context
}
