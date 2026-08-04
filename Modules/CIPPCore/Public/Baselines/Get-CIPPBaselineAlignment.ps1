function Get-CIPPBaselineAlignment {
    <#
    .SYNOPSIS
        Returns Baseline alignment data from the BaselineAlignment table.
    .DESCRIPTION
        Two view-shaped payloads per the Baseline contract:
        - -TenantFilter: summary scores, resolved rows (with run history from
          BaselineHistory), per-baseline stage states, and the deviation feed for one tenant.
        - -ByStandard: fleet score, per-standard aggregates, per-tenant summaries, and the
          accepted/suppressed deviation list across all tenants.
    .FUNCTIONALITY
        Internal
    #>
    [CmdletBinding()]
    param(
        $TenantFilter,
        [switch]$ByStandard,
        [switch]$History
    )

    $ResolvedTable = Get-CippTable -tablename 'BaselineAlignment'
    $Definitions = Get-CIPPBaselineDefinition

    # Historic view: every recorded run event for the tenant, flattened and newest-first.
    # History partitions are '<tenant>_<standard>', so a partition range scan covers them all.
    if ($TenantFilter -and $History) {
        $HistoryTable = Get-CippTable -tablename 'BaselineHistory'
        $SafeTenant = ConvertTo-CIPPODataFilterValue -Value $TenantFilter
        $Rows = Get-CIPPAzDataTableEntity @HistoryTable -Filter ("PartitionKey ge '{0}_' and PartitionKey lt '{0}{1}'" -f $SafeTenant, [char]0x60)
        $Events = foreach ($Row in $Rows) {
            if (-not $Row) { continue }
            $StandardName = "$($Row.PartitionKey)".Substring($TenantFilter.Length + 1)
            $BaseName = ($StandardName -split '#')[0]
            $Definition = $Definitions | Where-Object { $_.name -eq $BaseName } | Select-Object -First 1
            [PSCustomObject]@{
                timestamp     = $(if ($Row.Timestamp -is [System.DateTimeOffset]) { $Row.Timestamp.ToUnixTimeSeconds() } else { $Row.Timestamp })
                standardName  = $StandardName
                standardLabel = $Definition.label ?? $StandardName
                mode          = $Row.Mode
                triggeredBy   = $Row.TriggeredBy
                outcome       = $Row.Outcome
                remediated    = [bool]$Row.Remediated
                runId         = $Row.RunId
                diff          = $(if ($Row.Diff) { try { $Row.Diff | ConvertFrom-Json } catch { $null } } else { $null })
            }
        }
        return [PSCustomObject]@{ events = @($Events | Sort-Object -Property timestamp -Descending) }
    }

    $ScoreRows = {
        param($Rows)
        $Rows = @($Rows)
        $Total = $Rows.Count
        $LicenseMissing = @($Rows | Where-Object { $_.status -eq 'Skipped - No License' }).Count
        # 'No Data' rows are standards a baseline has rolled out that the engine has not
        # resolved yet - shown, but excluded from scoring like license-missing rows.
        $NoData = @($Rows | Where-Object { $_.status -eq 'No Data' }).Count
        $Applicable = $Total - $LicenseMissing - $NoData
        $Compliant = @($Rows | Where-Object { $_.status -eq 'Compliant' }).Count
        $Accepted = @($Rows | Where-Object { $_.status -eq 'Accepted' }).Count
        $Drift = @($Rows | Where-Object { $_.status -in @('Drift', 'Partially Accepted') }).Count
        $Denied = @($Rows | Where-Object { $_.status -like 'Denied - *' }).Count
        $Pct = { param($Count) if ($Applicable) { [math]::Round(($Count / $Applicable) * 100) } else { 0 } }
        @{
            total              = $Total
            applicable         = $Applicable
            licenseMissing     = $LicenseMissing
            noData             = $NoData
            compliant          = $Compliant
            accepted           = $Accepted
            drift              = $Drift
            denied             = $Denied
            verifiedPercentage = & $Pct $Compliant
            alignedPercentage  = & $Pct ($Compliant + $Accepted)
            acceptedPercentage = & $Pct $Accepted
        }
    }

    if ($TenantFilter) {
        $SafeTenant = ConvertTo-CIPPODataFilterValue -Value $TenantFilter
        $Entities = Get-CIPPAzDataTableEntity @ResolvedTable -Filter "PartitionKey eq '$SafeTenant'"
        $Rows = @($Entities | ForEach-Object { Convert-CIPPBaselineResolvedEntity -Entity $_ -Definitions $Definitions })

        # Attach the last runs from history (§4.3 columns; RowKey is inverted ticks so the
        # partition lists newest-first).
        $HistoryTable = Get-CippTable -tablename 'BaselineHistory'
        foreach ($Row in $Rows) {
            $SafeHistoryPk = ConvertTo-CIPPODataFilterValue -Value ('{0}_{1}' -f $TenantFilter, $Row.standardName)
            $HistoryRows = Get-CIPPAzDataTableEntity @HistoryTable -Filter "PartitionKey eq '$SafeHistoryPk'" -First 5
            $Row | Add-Member -NotePropertyName 'history' -NotePropertyValue @(
                $HistoryRows | ForEach-Object {
                    [PSCustomObject]@{
                        runId       = $_.RunId
                        timestamp   = $(if ($_.Timestamp -is [System.DateTimeOffset]) { $_.Timestamp.ToUnixTimeSeconds() } else { $_.Timestamp })
                        mode        = $_.Mode
                        triggeredBy = $_.TriggeredBy
                        outcome     = $_.Outcome
                        remediated  = [bool]$_.Remediated
                        diff        = if ($_.Diff) { try { $_.Diff | ConvertFrom-Json } catch { $null } } else { $null }
                    }
                }
            ) -Force
        }

        # Stage states for every baseline assigned to this tenant.
        $TenantGroupNames = @()
        try {
            $TenantGroupNames = @((Get-TenantGroups | Where-Object { $_.Members.defaultDomainName -contains $TenantFilter }).Name)
        } catch {
            Write-Information "Get-CIPPBaselineAlignment: tenant group lookup failed: $($_.Exception.Message)"
        }
        # Render a definition's %var% expected template from configured variable values: splice
        # the values into the serialized template ("%var%" as an exact JSON value keeps its
        # type), then Get-CIPPTextReplacement resolves tenant tokens.
        $RenderExpected = {
            param($Definition, $Variables)
            if (-not $Definition.expected) { return $null }
            $ExpectedJson = ConvertTo-Json -Compress -Depth 100 -InputObject $Definition.expected
            foreach ($Variable in ($Variables.PSObject.Properties ?? @())) {
                $Token = '%{0}%' -f $Variable.Name
                $EncodedValue = ConvertTo-Json -Compress -Depth 100 -InputObject $Variable.Value
                $ExpectedJson = $ExpectedJson.Replace(('"{0}"' -f $Token), $EncodedValue)
                $ExpectedJson = $ExpectedJson.Replace($Token, "$($Variable.Value)")
            }
            $ExpectedJson = Get-CIPPTextReplacement -TenantFilter $TenantFilter -Text $ExpectedJson -EscapeForJson
            $ExpectedJson | ConvertFrom-Json
        }

        $SynthesizedRows = [System.Collections.Generic.List[object]]::new()
        $KnownStandards = [System.Collections.Generic.List[string]]::new()
        foreach ($Known in $Rows.standardName) { $KnownStandards.Add($Known) }
        $StageStates = foreach ($Baseline in (Get-CIPPBaseline)) {
            if ($Baseline.excludedTenants -contains $TenantFilter) { continue }
            $Assigned = $Baseline.assignedTenants | Where-Object {
                $_ -eq 'AllTenants' -or $_ -eq $TenantFilter -or $TenantGroupNames -contains $_
            }
            if (-not $Assigned) { continue }
            # Get-CIPPBaseline defaults every assigned tenant without a rollout-state row to stage 1.
            $State = $Baseline.tenantStates | Where-Object { $_.tenantFilter -eq $TenantFilter } | Select-Object -First 1
            if (-not $State) { continue }

            # Aligned % against the standards this baseline has rolled out so far ('No Data'
            # rows carry no signal, so no percentage until the engine resolves something).
            $RolledOut = @($Baseline.stages | Select-Object -First $State.currentStage | ForEach-Object { @($_.standards) } | ForEach-Object { ($_ -split '#')[0] } | Select-Object -Unique)
            $RolledOutRows = @($Rows | Where-Object { $RolledOut -contains (($_.standardName -split '#')[0]) })
            $RolledOutScores = & $ScoreRows $RolledOutRows
            $AlignedPercentage = if ($RolledOutScores.applicable -gt 0) { $RolledOutScores.alignedPercentage } else { $null }

            # Every standard rolled out to this tenant (current + previous stages) that the
            # engine has not resolved yet appears as a 'No Data' row.
            foreach ($StageDef in ($Baseline.stages | Select-Object -First $State.currentStage)) {
                foreach ($InstanceKey in @($StageDef.standards)) {
                    if ($KnownStandards -contains $InstanceKey) { continue }
                    $KnownStandards.Add($InstanceKey)
                    $BaseName = ($InstanceKey -split '#')[0]
                    $Definition = $Definitions | Where-Object { $_.name -eq $BaseName } | Select-Object -First 1
                    $Config = $StageDef.standardsConfig | Where-Object { ($_.instance ?? $_.standard) -eq $InstanceKey } | Select-Object -First 1
                    $Expected = & $RenderExpected $Definition $Config.variables
                    $SynthesizedRows.Add([PSCustomObject]@{
                            tenantFilter        = $TenantFilter
                            tenantName          = $State.tenantName
                            standardName        = $InstanceKey
                            standardLabel       = $Definition.label ?? $InstanceKey
                            category            = $Definition.cat ?? 'Uncategorized'
                            impact              = $Definition.impact
                            secureScoreImpact   = $Definition.secureScoreImpact ?? 0
                            templateId          = $Baseline.GUID
                            expectedValue       = $Expected
                            currentValue        = $null
                            compliant           = $false
                            pendingVerification = $false
                            licenseAvailable    = $true
                            sourceScope         = 'baseline'
                            sourceTemplate      = $Baseline.templateName
                            stage               = $StageDef.name
                            inheritance         = @([PSCustomObject]@{
                                    templateName = $Baseline.templateName
                                    assignedTo   = ($Baseline.assignedTenants -join ', ')
                                    value        = $Expected
                                    effective    = $true
                                })
                            acceptedPaths       = [PSCustomObject]@{}
                            status              = 'No Data'
                            deviationReason     = $null
                            deviationBy         = $null
                            deviationAt         = $null
                            deviationExpires    = $null
                            remediateOnExpire   = $false
                            lastRun             = $null
                            lastRemediated      = $null
                            history             = @()
                        })
                }
            }

            $State | Select-Object *, @{n = 'templateId'; e = { $Baseline.GUID } }, @{n = 'templateName'; e = { $Baseline.templateName } }, @{n = 'alignedPercentage'; e = { $AlignedPercentage } }
        }
        $AllRows = [System.Collections.Generic.List[object]]::new()
        foreach ($Row in @($Rows)) { if ($Row) { $AllRows.Add($Row) } }
        foreach ($Row in $SynthesizedRows) { $AllRows.Add($Row) }
        $Rows = $AllRows

        # Ad-hoc tenant overrides are deltas with an empty templateId. Before the engine has
        # written a resolved row they exist only as deltas, so apply them at read time: the
        # override replaces the expected value on whichever row shows the standard, or gets
        # its own 'No Data' row when nothing else rolls the standard out to this tenant.
        $DeltaTable = Get-CippTable -tablename 'Baselines'
        $OverrideDeltas = Get-CIPPAzDataTableEntity @DeltaTable -Filter "PartitionKey eq 'standardItem' and scope eq 'tenant' and scopeId eq '$SafeTenant' and templateId eq ''"
        foreach ($Delta in @($OverrideDeltas)) {
            if (-not $Delta) { continue }
            $Variables = if ($Delta.expectedValue) { $Delta.expectedValue | ConvertFrom-Json } else { [PSCustomObject]@{} }
            $BaseName = ($Delta.standardName -split '#')[0]
            $Definition = $Definitions | Where-Object { $_.name -eq $BaseName } | Select-Object -First 1
            $Expected = & $RenderExpected $Definition $Variables
            $Row = $Rows | Where-Object { $_.standardName -eq $Delta.standardName } | Select-Object -First 1
            if ($Row) {
                if ($Row.sourceTemplate -ne 'Tenant Override') {
                    $Inheritance = [System.Collections.Generic.List[object]]::new()
                    foreach ($Tier in @($Row.inheritance)) {
                        if (-not $Tier -or $Tier.templateName -eq 'Tenant Override') { continue }
                        $Tier.effective = $false
                        $Inheritance.Add($Tier)
                    }
                    $Inheritance.Add([PSCustomObject]@{
                            templateName = 'Tenant Override'
                            assignedTo   = $TenantFilter
                            value        = $Expected
                            effective    = $true
                        })
                    $Row.expectedValue = $Expected
                    $Row.sourceScope = 'tenant'
                    $Row.sourceTemplate = 'Tenant Override'
                    $Row.inheritance = @($Inheritance)
                }
            } else {
                $Rows.Add([PSCustomObject]@{
                        tenantFilter        = $TenantFilter
                        tenantName          = ($Rows | Select-Object -First 1).tenantName ?? $TenantFilter
                        standardName        = $Delta.standardName
                        standardLabel       = $Definition.label ?? $Delta.standardName
                        category            = $Definition.cat ?? 'Uncategorized'
                        impact              = $Definition.impact
                        secureScoreImpact   = $Definition.secureScoreImpact ?? 0
                        templateId          = ''
                        expectedValue       = $Expected
                        currentValue        = $null
                        compliant           = $false
                        pendingVerification = $false
                        licenseAvailable    = $true
                        sourceScope         = 'tenant'
                        sourceTemplate      = 'Tenant Override'
                        stage               = $null
                        inheritance         = @([PSCustomObject]@{
                                templateName = 'Tenant Override'
                                assignedTo   = $TenantFilter
                                value        = $Expected
                                effective    = $true
                            })
                        acceptedPaths       = [PSCustomObject]@{}
                        status              = 'No Data'
                        deviationReason     = $null
                        deviationBy         = $null
                        deviationAt         = $null
                        deviationExpires    = $null
                        remediateOnExpire   = $false
                        lastRun             = $null
                        lastRemediated      = $null
                        history             = @()
                    })
            }
        }

        # Chronological deviation feed derived from the resolved rows.
        $Feed = foreach ($Row in $Rows) {
            if ($Row.status -in @('Drift', 'Partially Accepted')) {
                [PSCustomObject]@{ timestamp = $Row.lastRun; feedEvent = 'Drift'; standardLabel = $Row.standardLabel; detail = "Drift detected by the $($Row.sourceTemplate) run"; by = 'CIPP' }
            }
            if ($Row.status -eq 'Accepted' -or $Row.status -like 'Denied - *') {
                [PSCustomObject]@{ timestamp = $Row.deviationAt; feedEvent = $Row.status; standardLabel = $Row.standardLabel; detail = $Row.deviationReason; by = $Row.deviationBy }
            }
            foreach ($Path in ($Row.acceptedPaths.PSObject.Properties ?? @())) {
                [PSCustomObject]@{ timestamp = $Path.Value.at; feedEvent = 'Property Accepted'; standardLabel = $Row.standardLabel; detail = "$($Path.Name): $($Path.Value.reason)"; by = $Path.Value.by }
            }
            if ($Row.lastRemediated) {
                $Detail = if ($Row.pendingVerification) { 'Auto-remediated - awaiting verification on the next run' } else { 'Auto-remediated to the expected value' }
                [PSCustomObject]@{ timestamp = $Row.lastRemediated; feedEvent = 'Remediated'; standardLabel = $Row.standardLabel; detail = $Detail; by = 'CIPP' }
            }
        }

        $Summary = & $ScoreRows $Rows
        $Summary.tenantFilter = $TenantFilter
        $Summary.tenantId = $TenantFilter
        $Summary.displayName = ($Rows | Select-Object -First 1).tenantName ?? $TenantFilter

        return [PSCustomObject]@{
            summary       = [PSCustomObject]$Summary
            rows          = @($Rows)
            stageStates   = @($StageStates)
            deviationFeed = @($Feed | Sort-Object -Property timestamp -Descending)
        }
    }

    if ($ByStandard) {
        $Entities = Get-CIPPAzDataTableEntity @ResolvedTable -Filter "PartitionKey ne ''"
        $Rows = @($Entities | ForEach-Object { Convert-CIPPBaselineResolvedEntity -Entity $_ -Definitions $Definitions })

        $Standards = foreach ($Group in ($Rows | Group-Object -Property standardName)) {
            $First = $Group.Group | Select-Object -First 1
            $Scores = & $ScoreRows $Group.Group
            [PSCustomObject]([ordered]@{
                    standardName      = $Group.Name
                    standardLabel     = $First.standardLabel
                    category          = $First.category
                    impact            = $First.impact
                    secureScoreImpact = $First.secureScoreImpact
                    totalTenants      = $Scores.total
                    rows              = @($Group.Group)
                } + $Scores)
        }

        $Tenants = foreach ($Group in ($Rows | Group-Object -Property tenantFilter)) {
            $Scores = & $ScoreRows $Group.Group
            [PSCustomObject]([ordered]@{
                    tenantFilter = $Group.Name
                    tenantId     = $Group.Name
                    displayName  = ($Group.Group | Select-Object -First 1).tenantName ?? $Group.Name
                } + $Scores)
        }

        $Fleet = & $ScoreRows $Rows
        # Until the engine writes daily history rollups, the trend is today's live score so the
        # chart renders as soon as resolved data exists.
        $Trend = if ($Rows.Count -gt 0) {
            @([PSCustomObject]@{
                    date     = (Get-Date).ToUniversalTime().ToString('yyyy-MM-dd')
                    aligned  = $Fleet.alignedPercentage
                    verified = $Fleet.verifiedPercentage
                })
        } else { @() }

        return [PSCustomObject]@{
            fleet            = [PSCustomObject]$Fleet
            standards        = @($Standards)
            tenants          = @($Tenants)
            trend            = $Trend
            activeDeviations = @($Rows | Where-Object { $_.status -in @('Accepted', 'Partially Accepted') -or $_.status -like 'Denied - *' })
        }
    }

    throw 'Specify -TenantFilter or -ByStandard.'
}
