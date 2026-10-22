function Get-CIPPBaselineAlignment {
    <#
    .SYNOPSIS
        Returns Baseline alignment data from the BaselineAlignment table.
    .DESCRIPTION
        Two view-shaped payloads per the Baseline contract:
        - -TenantFilter: summary scores, resolved rows, per-baseline stage states, and the
          deviation feed for one tenant. Run history is read separately with -History.
        - -TenantFilter -History: run events newest-first, filtered in the table query by
          -Since (unix seconds), -Standard / -Outcome / -Mode (any of the given values).
          With -PageSize it returns one page and Metadata.nextLink (the last RowKey); pass that
          back as -After for the next, older page. Without -PageSize it returns every match.
        - -ByStandard: fleet score, per-standard aggregates, per-tenant summaries, and the
          accepted/suppressed deviation list across all tenants.
    .PARAMETER BaselineId
        -ByStandard only: limit the aggregate to one baseline (its GUID). Keeps the rows of
        tenants assigned to it, for the standards it has rolled out to each tenant (stages up
        to the tenant's current stage). Rows are per tenant + standard, so a standard shared
        by several baselines counts toward each of them. Stored trends are fleet-wide, so a
        filtered trend holds only today's live point, and the payload carries a 'filter' object.
    .PARAMETER Stage
        -ByStandard with -BaselineId only: the 1-based stage number. Keeps only that stage's
        standards, for tenants that have reached it.
    .FUNCTIONALITY
        Internal
    #>
    [CmdletBinding()]
    param(
        $TenantFilter,
        [switch]$ByStandard,
        [switch]$History,
        [string[]]$Standard,
        [string[]]$Outcome,
        [string[]]$Mode,
        [long]$Since,
        [int]$PageSize,
        [string]$After,
        [string]$BaselineId,
        [int]$Stage
    )

    $ResolvedTable = Get-CippTable -tablename 'BaselineAlignment'
    $Definitions = Get-CIPPBaselineDefinition

    # Lazy template-name lookup for identity-carrying standards. The definition's
    # optional identity block names the partition and name field; the defaults
    # (partition = the remediate executor name, name field = displayName) are the
    # CA/Intune convention. Loaded once per partition+field, only when a row actually
    # needs it. Rows written before the prepare ran (Conflict, license-skip) carry the
    # raw template id as their displayName - every labeling path resolves it to the
    # template's real name.
    $TemplateNameMaps = @{}
    $ResolveTemplateName = {
        param($Partition, $Id, $NameField)
        if (-not $Partition -or -not $Id) { return $null }
        if ([string]::IsNullOrWhiteSpace($NameField)) { $NameField = 'displayName' }
        $MapKey = "$Partition|$NameField"
        if (-not $TemplateNameMaps.ContainsKey($MapKey)) {
            $Map = @{}
            try {
                $TemplatesTable = Get-CippTable -tablename 'templates'
                $SafePartition = ConvertTo-CIPPODataFilterValue -Value $Partition
                foreach ($TemplateRow in @(Get-CIPPAzDataTableEntity @TemplatesTable -Filter "PartitionKey eq '$SafePartition'")) {
                    $TemplateName = $(try { ($TemplateRow.JSON | ConvertFrom-Json).$NameField } catch { $null })
                    if ($TemplateName) {
                        $Map["$($TemplateRow.RowKey)"] = $TemplateName
                        if ($TemplateRow.GUID) { $Map["$($TemplateRow.GUID)"] = $TemplateName }
                    }
                }
            } catch {
                Write-Information "Get-CIPPBaselineAlignment: template name lookup for $Partition failed: $($_.Exception.Message)"
            }
            $TemplateNameMaps[$MapKey] = $Map
        }
        $TemplateNameMaps[$MapKey]["$Id"]
    }

    # Historic view: run events for the tenant, newest-first. History partitions are
    # '<tenant>_<standard>' with an inverted-ticks RowKey, so each partition already lists
    # newest-first and a RowKey bound is a time bound.
    if ($TenantFilter -and $History) {
        $HistoryTable = Get-CippTable -tablename 'BaselineHistory'
        $SafeTenant = ConvertTo-CIPPODataFilterValue -Value $TenantFilter
        $DefinitionByName = @{}
        foreach ($Definition in $Definitions) { $DefinitionByName["$($Definition.name)"] = $Definition }
        $AnyOf = {
            param($Property, $Values)
            '({0})' -f (@(foreach ($Value in $Values) { "$Property eq '{0}'" -f (ConvertTo-CIPPODataFilterValue -Value $Value) }) -join ' or ')
        }
        $MaxTicks = [DateTime]::MaxValue.Ticks
        $SinceKey = if ($Since) { '{0:D19}' -f ($MaxTicks - [DateTimeOffset]::FromUnixTimeSeconds($Since).UtcTicks) }
        $Filters = @(
            if ($Outcome) { & $AnyOf 'Outcome' $Outcome }
            if ($Mode) { & $AnyOf 'Mode' $Mode }
        )
        # Inverted ticks: RowKey gt $Older is older than that key, RowKey lt $Newer is newer.
        $Read = {
            param($PartitionFilter, $Older, $Newer, $First)
            $Query = @{
                Filter = @(
                    $PartitionFilter
                    if ($Older) { "RowKey gt '{0}'" -f (ConvertTo-CIPPODataFilterValue -Value $Older) }
                    if ($Newer) { "RowKey lt '{0}'" -f (ConvertTo-CIPPODataFilterValue -Value $Newer) }
                    $Filters
                ) -join ' and '
            }
            if ($First) { $Query.First = $First }
            Get-CIPPAzDataTableEntity @HistoryTable @Query
        }
        $TenantRange = "PartitionKey ge '{0}_' and PartitionKey lt '{0}{1}'" -f $SafeTenant, [char]0x60
        $Exhausted = $true
        $Rows = if ($Standard) {
            foreach ($Name in $Standard) {
                $SafeHistoryPk = ConvertTo-CIPPODataFilterValue -Value ('{0}_{1}' -f $TenantFilter, ($Name -replace '#', '~'))
                $PartitionRows = @(& $Read "PartitionKey eq '$SafeHistoryPk'" $After $SinceKey $PageSize)
                if ($PageSize -and $PartitionRows.Count -ge $PageSize) { $Exhausted = $false }
                $PartitionRows
            }
        } elseif (-not $PageSize) {
            & $Read $TenantRange $After $SinceKey
        } else {
            # A RowKey bound is not indexed across partitions, but the service bills a slice by
            # the rows it returns, so walk back from the cursor in widening slices until a page
            # fills, sizing each from the density so far. The last slice is open-ended (or stops
            # at -Since), so the walk terminates.
            $CursorTicks = if ($After) { [long]$After.Substring(0, 19) } else { $MaxTicks - [DateTime]::UtcNow.Ticks }
            $SliceStart = $After
            $Hours = 24
            $Collected = [System.Collections.Generic.List[object]]::new()
            do {
                $SliceEnd = '{0:D19}' -f ($CursorTicks + [TimeSpan]::FromHours($Hours).Ticks)
                $LastSlice = $Hours -gt 24 * 180
                if ($SinceKey -and ($LastSlice -or [string]::CompareOrdinal($SliceEnd, $SinceKey) -ge 0)) {
                    $SliceEnd = $SinceKey
                    $LastSlice = $true
                } elseif ($LastSlice) {
                    $SliceEnd = $null
                }
                foreach ($Row in @(& $Read $TenantRange $SliceStart $SliceEnd)) { $Collected.Add($Row) }
                $SliceStart = $SliceEnd
                $Hours = if ($Collected.Count) { [Math]::Max($Hours * 2, [Math]::Ceiling($PageSize * $Hours / $Collected.Count * 1.25)) } else { $Hours * 4 }
            } until ($Collected.Count -ge $PageSize -or $LastSlice)
            if (-not $LastSlice) { $Exhausted = $false }
            $Collected
        }
        $Rows = @(@($Rows).Where({ $_ }) | Sort-Object -Property RowKey)
        if ($PageSize -and $Rows.Count -gt $PageSize) {
            $Rows = $Rows[0..($PageSize - 1)]
            $Exhausted = $false
        }
        $NextLink = if (-not $Exhausted -and $Rows.Count) { $Rows[-1].RowKey }
        # Multi-instance standards share one definition label; the resolved rows carry
        # each instance's identity (task name / deployed template displayName), so
        # timeline events can show it too.
        $ManualLabels = @{}
        $ResolvedFilter = if ($Standard) {
            "PartitionKey eq '$SafeTenant' and {0}" -f (& $AnyOf 'StandardName' $Standard)
        } else {
            "PartitionKey eq '$SafeTenant'"
        }
        foreach ($Resolved in @(Get-CIPPAzDataTableEntity @ResolvedTable -Filter $ResolvedFilter)) {
            $ResolvedBase = ("$($Resolved.StandardName)" -split '#')[0]
            $ResolvedDefinition = $DefinitionByName[$ResolvedBase]
            $Suffix = $(try { ($Resolved.Manual | ConvertFrom-Json).taskName } catch { $null })
            if (-not $Suffix -and $ResolvedDefinition.instanceIdentity) {
                $Suffix = $(try { ($Resolved.ExpectedValue | ConvertFrom-Json).displayName } catch { $null })
                # Presence-shaped families carry no name in Expected; the identity
                # variable on the effective Inheritance entry is the configured id.
                if (-not $Suffix) {
                    $Suffix = $(try {
                            $Effective = @($Resolved.Inheritance | ConvertFrom-Json) | Where-Object { $_.effective } | Select-Object -First 1
                            $Value = $Effective.value.$($ResolvedDefinition.instanceIdentity)
                            $Value.value ?? $Value
                        } catch { $null })
                }
                if ($Suffix) {
                    $Partition = "$($ResolvedDefinition.identity.partition ?? $ResolvedDefinition.remediate.executor)"
                    $NameField = "$($ResolvedDefinition.identity.nameField ?? 'displayName')"
                    $Suffix = (& $ResolveTemplateName $Partition "$Suffix" $NameField) ?? $Suffix
                }
            }
            if ($Suffix) { $ManualLabels[$Resolved.StandardName] = '{0} - {1}' -f ($ResolvedDefinition.label ?? $ResolvedBase), $Suffix }
        }
        $Events = foreach ($Row in $Rows) {
            # Reverse the '#'->'~' key sanitization to recover the instance key.
            $StandardName = "$($Row.PartitionKey)".Substring($TenantFilter.Length + 1) -replace '~', '#'
            $Definition = $DefinitionByName[($StandardName -split '#')[0]]
            [PSCustomObject]@{
                timestamp     = $(if ($Row.Timestamp -is [System.DateTimeOffset]) { $Row.Timestamp.ToUnixTimeSeconds() } else { $Row.Timestamp })
                standardName  = $StandardName
                standardLabel = $ManualLabels[$StandardName] ?? $Definition.label ?? $StandardName
                mode          = $Row.Mode
                triggeredBy   = $Row.TriggeredBy
                outcome       = $Row.Outcome
                remediated    = [bool]$Row.Remediated
                runId         = $Row.RunId
                detail        = "$($Row.Detail)"
                alerted       = [bool]$Row.Alerted
                diff          = $(if ($Row.Diff) { try { $Row.Diff | ConvertFrom-Json } catch { $null } } else { $null })
            }
        }
        return [PSCustomObject]@{ events = @($Events); Metadata = @{ nextLink = $NextLink } }
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
        $Conflicts = @($Rows | Where-Object { $_.status -eq 'Conflict' }).Count
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
            conflicts          = $Conflicts
            verifiedPercentage = & $Pct $Compliant
            alignedPercentage  = & $Pct ($Compliant + $Accepted)
            acceptedPercentage = & $Pct $Accepted
        }
    }

    if ($TenantFilter) {
        $SafeTenant = ConvertTo-CIPPODataFilterValue -Value $TenantFilter
        $Entities = Get-CIPPAzDataTableEntity @ResolvedTable -Filter "PartitionKey eq '$SafeTenant'"
        $Rows = @($Entities | ForEach-Object { Convert-CIPPBaselineResolvedEntity -Entity $_ -Definitions $Definitions -ResolveTemplateName $ResolveTemplateName })

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
            $RolledOut = @(Get-CIPPBaselineStageStandards -Baseline $Baseline -Definitions $Definitions | Select-Object -First $State.currentStage | ForEach-Object { $_ })
            $RolledOutRows = @($Rows | Where-Object { $RolledOut -contains $_.standardName })
            $RolledOutScores = & $ScoreRows $RolledOutRows
            $AlignedPercentage = if ($RolledOutScores.applicable -gt 0) { $RolledOutScores.alignedPercentage } else { $null }

            # Every standard rolled out to this tenant (current + previous stages) that the
            # engine has not resolved yet appears as a 'No Data' row.
            foreach ($StageDef in ($Baseline.stages | Select-Object -First $State.currentStage)) {
                foreach ($StageInstanceKey in @($StageDef.standards)) {
                    if ($KnownStandards -contains $StageInstanceKey) { continue }
                    $KnownStandards.Add($StageInstanceKey)
                    $StageBaseName = ($StageInstanceKey -split '#')[0]
                    $StageDefinition = $Definitions | Where-Object { $_.name -eq $StageBaseName } | Select-Object -First 1
                    $StageConfig = $StageDef.standardsConfig | Where-Object { ($_.instance ?? $_.standard) -eq $StageInstanceKey } | Select-Object -First 1
                    # Package standards never resolve under their own key: synthesize one
                    # row per MEMBER, with the same derived instance keys the work-item
                    # resolver produces - pre-run 'No Data' rows then meld into the
                    # engine's resolved rows instead of leaving a phantom package row.
                    $SynthTargets = if ($StageDefinition.package) {
                        $MemberDefinition = $Definitions | Where-Object { $_.name -eq "$($StageDefinition.package.memberStandard)" } | Select-Object -First 1
                        @(Expand-CIPPBaselineTemplatePackage -Definition $StageDefinition -Config $StageConfig | ForEach-Object {
                                [PSCustomObject]@{ InstanceKey = $_.instance; Definition = $MemberDefinition; Config = $_ }
                            })
                    } else {
                        @([PSCustomObject]@{ InstanceKey = $StageInstanceKey; Definition = $StageDefinition; Config = $StageConfig })
                    }
                    foreach ($SynthTarget in $SynthTargets) {
                    $InstanceKey = $SynthTarget.InstanceKey
                    $Definition = $SynthTarget.Definition
                    $Config = $SynthTarget.Config
                    if ($StageDefinition.package) {
                        if ($KnownStandards -contains $InstanceKey) { continue }
                        $KnownStandards.Add($InstanceKey)
                    }
                    $Expected = & $RenderExpected $Definition $Config.variables
                    # Multi-instance labels carry the instance identity before the first
                    # run too: the task name for manual tasks; for identity-carrying
                    # standards the configured id resolves to the template's name via
                    # the template store, at the definition's declared partition/field.
                    $SynthIdentity = if ($Definition.manual -and $Config.variables.taskName) {
                        $Config.variables.taskName
                    } elseif ($Definition.instanceIdentity) {
                        $IdentityValue = $Config.variables.$($Definition.instanceIdentity)
                        $IdentityValue = $IdentityValue.value ?? $IdentityValue
                        $Partition = "$($Definition.identity.partition ?? $Definition.remediate.executor)"
                        $NameField = "$($Definition.identity.nameField ?? 'displayName')"
                        (& $ResolveTemplateName $Partition "$IdentityValue" $NameField) ?? $IdentityValue
                    }
                    $SynthLabel = if ($SynthIdentity) { '{0} - {1}' -f ($Definition.label ?? $InstanceKey), $SynthIdentity } else { $Definition.label ?? $InstanceKey }
                    $SynthesizedRows.Add([PSCustomObject]@{
                            tenantFilter        = $TenantFilter
                            tenantName          = $State.tenantName
                            standardName        = $InstanceKey
                            standardLabel       = $SynthLabel
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
                            sourceTemplate      = $(if ($Config.fromPackage) { '{0} ({1})' -f $Baseline.templateName, $Config.fromPackage } else { $Baseline.templateName })
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

        # This tenant's trend: the daily rollups Set-CIPPBaselineTrendPoint writes (last
        # 90 days), with today's point always replaced by the LIVE score - same shape as
        # the fleet trend so the same chart renders it.
        $Today = (Get-Date).ToUniversalTime().ToString('yyyy-MM-dd')
        $Trend = [System.Collections.Generic.List[object]]::new()
        try {
            $TrendTable = Get-CippTable -tablename 'BaselineTrend'
            $Cutoff = (Get-Date).ToUniversalTime().AddDays(-90).ToString('yyyy-MM-dd')
            $TrendRows = @(Get-CIPPAzDataTableEntity @TrendTable -Filter "PartitionKey eq 'tenant_$SafeTenant' and RowKey ge '$Cutoff' and RowKey lt '$Today'") | Sort-Object -Property RowKey
            foreach ($Point in $TrendRows) {
                $Trend.Add([PSCustomObject]@{ date = $Point.RowKey; aligned = [int]$Point.Aligned; verified = [int]$Point.Verified })
            }
        } catch {
            Write-Information "Baseline tenant trend read skipped: $($_.Exception.Message)"
        }
        if ($Rows.Count -gt 0) {
            $Trend.Add([PSCustomObject]@{ date = $Today; aligned = $Summary.alignedPercentage; verified = $Summary.verifiedPercentage })
        }

        return [PSCustomObject]@{
            summary       = [PSCustomObject]$Summary
            rows          = @($Rows)
            stageStates   = @($StageStates)
            deviationFeed = @($Feed | Sort-Object -Property timestamp -Descending)
            trend         = @($Trend)
        }
    }

    if ($ByStandard) {
        $Entities = Get-CIPPAzDataTableEntity @ResolvedTable -Filter "PartitionKey ne ''"
        $Rows = @($Entities | ForEach-Object { Convert-CIPPBaselineResolvedEntity -Entity $_ -Definitions $Definitions -ResolveTemplateName $ResolveTemplateName })

        $FilterInfo = $null
        if ($Stage -and -not $BaselineId) { throw 'Stage requires BaselineId.' }
        if ($BaselineId) {
            $FilterBaseline = Get-CIPPBaseline -ID $BaselineId | Select-Object -First 1
            if (-not $FilterBaseline) { throw "Baseline '$BaselineId' was not found." }
            $StageKeys = @(Get-CIPPBaselineStageStandards -Baseline $FilterBaseline -Definitions $Definitions)
            if ($Stage -and ($Stage -lt 1 -or $Stage -gt $StageKeys.Count)) { throw "Baseline '$($FilterBaseline.templateName)' has no stage $Stage." }
            # Tenant -> instance keys this baseline has rolled out to it.
            $Allowed = @{}
            foreach ($State in @($FilterBaseline.tenantStates)) {
                if ($FilterBaseline.excludedTenants -contains $State.tenantFilter) { continue }
                $Keys = if ($Stage) {
                    if ($State.currentStage -ge $Stage) { $StageKeys[$Stage - 1] }
                } else {
                    $StageKeys | Select-Object -First $State.currentStage | ForEach-Object { $_ }
                }
                $Allowed["$($State.tenantFilter)"] = [System.Collections.Generic.HashSet[string]]::new([string[]]@($Keys | Where-Object { $_ }), [System.StringComparer]::OrdinalIgnoreCase)
            }
            $Rows = @($Rows | Where-Object { $Allowed.ContainsKey("$($_.tenantFilter)") -and $Allowed["$($_.tenantFilter)"].Contains("$($_.standardName)") })
            $FilterInfo = [PSCustomObject]@{
                baselineId   = $FilterBaseline.GUID
                baselineName = $FilterBaseline.templateName
                stage        = $(if ($Stage) { $Stage } else { $null })
                stageName    = $(if ($Stage) { @($FilterBaseline.stages)[$Stage - 1].name } else { $null })
            }
        }

        # Per-standard trends in ONE range scan over the 'standard_*' partitions (keys
        # sanitize '#' to '~'), attached to each standard so the offcanvas charts without
        # another call. Today's point is always the LIVE score, appended per group below.
        $Today = (Get-Date).ToUniversalTime().ToString('yyyy-MM-dd')
        $StandardTrends = @{}
        # Stored trends are fleet-wide; a filtered view only has today's live point.
        if (-not $FilterInfo) {
            try {
                $TrendTable = Get-CippTable -tablename 'BaselineTrend'
                $Cutoff = (Get-Date).ToUniversalTime().AddDays(-90).ToString('yyyy-MM-dd')
                $StandardTrendRows = @(Get-CIPPAzDataTableEntity @TrendTable -Filter ("PartitionKey ge 'standard_' and PartitionKey lt 'standard{0}' and RowKey ge '{1}' and RowKey lt '{2}'" -f [char]0x60, $Cutoff, $Today))
                foreach ($Point in ($StandardTrendRows | Sort-Object -Property RowKey)) {
                    $StandardKey = "$($Point.PartitionKey)".Substring(9) -replace '~', '#'
                    if (-not $StandardTrends.ContainsKey($StandardKey)) {
                        $StandardTrends[$StandardKey] = [System.Collections.Generic.List[object]]::new()
                    }
                    $StandardTrends[$StandardKey].Add([PSCustomObject]@{ date = $Point.RowKey; aligned = [int]$Point.Aligned; verified = [int]$Point.Verified })
                }
            } catch {
                Write-Information "Baseline standard trend read skipped: $($_.Exception.Message)"
            }
        }

        $Standards = foreach ($Group in ($Rows | Group-Object -Property standardName)) {
            $First = $Group.Group | Select-Object -First 1
            $Scores = & $ScoreRows $Group.Group
            $TrendPoints = [System.Collections.Generic.List[object]]::new()
            foreach ($Point in @($StandardTrends[$Group.Name] ?? @())) { $TrendPoints.Add($Point) }
            $TrendPoints.Add([PSCustomObject]@{ date = $Today; aligned = $Scores.alignedPercentage; verified = $Scores.verifiedPercentage })
            [PSCustomObject]([ordered]@{
                    standardName      = $Group.Name
                    standardLabel     = $First.standardLabel
                    category          = $First.category
                    impact            = $First.impact
                    secureScoreImpact = $First.secureScoreImpact
                    totalTenants      = $Scores.total
                    rows              = @($Group.Group)
                    trend             = @($TrendPoints)
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
        # Trend = the daily rollups Set-CIPPBaselineTrendPoint writes after every run, capped
        # at 14 days (13 stored days + today), with today's point always replaced by the LIVE
        # score so the chart never lags the rest of the page.
        $Today = (Get-Date).ToUniversalTime().ToString('yyyy-MM-dd')
        $Trend = [System.Collections.Generic.List[object]]::new()
        if (-not $FilterInfo) {
            try {
                $TrendTable = Get-CippTable -tablename 'BaselineTrend'
                $Cutoff = (Get-Date).ToUniversalTime().AddDays(-13).ToString('yyyy-MM-dd')
                $TrendRows = @(Get-CIPPAzDataTableEntity @TrendTable -Filter "PartitionKey eq 'fleet' and RowKey ge '$Cutoff' and RowKey lt '$Today'") | Sort-Object -Property RowKey
                foreach ($Point in $TrendRows) {
                    $Trend.Add([PSCustomObject]@{ date = $Point.RowKey; aligned = [int]$Point.Aligned; verified = [int]$Point.Verified })
                }
            } catch {
                Write-Information "Baseline trend read skipped: $($_.Exception.Message)"
            }
        }
        if ($Rows.Count -gt 0) {
            $Trend.Add([PSCustomObject]@{ date = $Today; aligned = $Fleet.alignedPercentage; verified = $Fleet.verifiedPercentage })
        }
        $Trend = @($Trend)

        $Result = [PSCustomObject]@{
            fleet            = [PSCustomObject]$Fleet
            standards        = @($Standards)
            tenants          = @($Tenants)
            trend            = $Trend
            activeDeviations = @($Rows | Where-Object { $_.status -in @('Accepted', 'Partially Accepted') -or $_.status -like 'Denied - *' })
        }
        if ($FilterInfo) { $Result | Add-Member -NotePropertyName 'filter' -NotePropertyValue $FilterInfo }
        return $Result
    }

    throw 'Specify -TenantFilter or -ByStandard.'
}
