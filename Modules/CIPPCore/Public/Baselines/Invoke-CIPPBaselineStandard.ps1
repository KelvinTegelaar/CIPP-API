function Invoke-CIPPBaselineStandard {
    <#
    .SYNOPSIS
        Runs one standard instance against one tenant: read, compare, triage, remediate, persist.
    .DESCRIPTION
        The engine for a single (tenant, standard) work item from Get-CIPPBaselineWorkItems.
        Licensing is handled upstream: Start-CIPPBaselineOrchestrator strips unlicensed pairs
        before anything runs. Work items arrive through the durable pipeline as Hashtables -
        everything item-derived is normalized before use. Flow:
        1. manual definitions track operator completion on the resolved row (reopen on the
           configured recurrence); custom definitions delegate to their own
           Invoke-CIPPBaseline<StandardName> script.
        2. Read the current value from the CIPPDb cache (cacheType -> optional array
           dot-path descend/flatten -> filter[] (properties may be dot-paths) -> object
           dot-path). On a cache miss the engine triggers the central collector for that
           cacheType and re-reads once; if there is still nothing, NOTHING is written - the
           row stays 'No Data' and retries naturally on the next run.
        3. Render the expected template from the configured variable values, project the
           current value to the expected keys and compare with Compare-CIPPIntuneObject
           (subset). Differences on accepted property paths are tolerated.
        4. One Status per row: Compliant / Drift / Accepted / Partially Accepted /
           Denied - Remediate Pending / Denied - Delete Pending / Skipped - No License.
           Accepted holds until its unix expiry (optionally remediating on lapse); a row
           whose drift is fully covered by accepted property paths also scores Accepted,
           and partially covered drift scores Partially Accepted. Denied - Remediate
           Pending forces remediation regardless of the configured posture. Writes only
           happen when needed: drift, -Force (manual runs), or "checkBeforeRun": false
           definitions - and never while accepted paths cover live drift, because a write
           deploys the whole expected object.
        5. Persist the resolved row + a history row via Set-CIPPBaselineResult.
        Modes: run (all steps), compare (never writes), oneoff (remediation forced on).
    .FUNCTIONALITY
        Internal
    #>
    [CmdletBinding()]
    param(
        $Item,
        [ValidateSet('run', 'compare', 'oneoff')]$Mode = 'run',
        $TriggeredBy = 'schedule',
        [switch]$Force,
        $RunId
    )
    if (-not $RunId) { $RunId = [string](New-Guid).Guid }

    $TenantFilter = $Item.TenantFilter
    $Now = [int64]([datetimeoffset]::UtcNow.ToUnixTimeSeconds())

    # Render a %var% template from this item's variable values: splice each value into the
    # serialized template ("%var%" as an exact JSON token keeps its type), then
    # Get-CIPPTextReplacement resolves tenant tokens - one %var% syntax. The durable pipeline
    # hands the item back as Hashtables, so variables are normalized before enumeration.
    $Render = {
        param($Template, $Variables)
        if ($null -eq $Template) { return $null }
        if ($Variables -is [System.Collections.IDictionary]) { $Variables = [PSCustomObject]$Variables }
        $Json = ConvertTo-Json -Compress -Depth 100 -InputObject $Template
        foreach ($Variable in (($Variables ?? [PSCustomObject]@{}).PSObject.Properties)) {
            $Token = '%{0}%' -f $Variable.Name
            $EncodedValue = ConvertTo-Json -Compress -Depth 100 -InputObject $Variable.Value
            $Json = $Json.Replace(('"{0}"' -f $Token), $EncodedValue)
            $Json = $Json.Replace($Token, "$($Variable.Value)")
        }
        $Json = Get-CIPPTextReplacement -TenantFilter $TenantFilter -Text $Json -EscapeForJson
        $Json | ConvertFrom-Json
    }

    try {
        $Definition = Get-CIPPBaselineDefinition -Name $Item.BaseName
        if (-not $Definition) { throw "No definition found for standard $($Item.BaseName)." }
        # Package standards are authoring artifacts: the work-item resolver expands them
        # into member instances before anything is queued. One reaching the engine is a
        # resolver bug - fail loudly rather than comparing a package against nothing.
        if ($Definition.package) { throw "Package standard $($Item.BaseName) must be expanded by the resolver and never executes directly." }
        $Label = $Definition.label ?? $Item.Standard

        # License gate (moved out of the starter so Run Baseline Now responds instantly -
        # the capability lookup happens here, parallel across the durable workers). The
        # capabilities cache is per tenant with a 24h TTL, so at most one Graph call per
        # tenant per day. A oneoff is an explicit operator ask and bypasses the gate - the
        # cache may not know about a license bought after the last sync.
        $Required = @($Definition.requiredCapabilities)
        if ($Required.Count -gt 0 -and $Mode -ne 'oneoff') {
            $Capabilities = $(try { Get-CIPPTenantCapabilities -TenantFilter $TenantFilter } catch { $null })
            if (@($Required | Where-Object { $Capabilities.$_ -eq $true }).Count -eq 0) {
                $Skipped = [PSCustomObject]@{
                    Item                = $Item
                    Mode                = $Mode
                    TriggeredBy         = $TriggeredBy
                    ExpectedValue       = $null
                    CurrentValue        = $null
                    Compliant           = $false
                    PendingVerification = $false
                    LicenseAvailable    = $false
                    Status              = 'Skipped - No License'
                    Remediated          = $false
                    Outcome             = 'Skipped-License'
                    Diff                = $null
                    Inheritance         = @($Item.Tiers)
                    AlertEvent          = $null
                    CacheType           = $null
                }
                Set-CIPPBaselineResult -Result $Skipped -Prior $null -RunId $RunId
                return $Skipped
            }
        }

        Write-LogMessage -API 'Baselines' -tenant $TenantFilter -message "Started `"$Label`" ($Mode) - Run $RunId" -Sev 'Info'

        # 1a. Custom standards own their whole flow in their per-standard script.
        if ($Definition.custom -eq $true) {
            $CustomFunction = Get-Command -Name $Definition.customFunction -ErrorAction SilentlyContinue
            if (-not $CustomFunction) { throw "Custom function $($Definition.customFunction) is not available." }
            return (& $Definition.customFunction -Item $Item -Mode $Mode -TriggeredBy $TriggeredBy -Force:$Force -RunId $RunId)
        }

        # Prior resolved row: the deviation lifecycle and manual completion live on it.
        $ResolvedTable = Get-CippTable -tablename 'BaselineAlignment'
        $SafeTenant = ConvertTo-CIPPODataFilterValue -Value $TenantFilter
        $SafeStandard = ConvertTo-CIPPODataFilterValue -Value $Item.Standard
        # $anyOf: an expected property may declare several acceptable values, e.g.
        # { "$anyOf": ["migrationComplete", null] } - null and 'migrationComplete' both
        # mean the auth-policy migration is done. Resolved here so Compare-CIPPIntuneObject
        # stays untouched: with -UseCurrent, a current value inside the set resolves to
        # itself (the compare sees a match); everywhere the value is displayed or deployed,
        # the first non-null entry is the canonical expected value. %var% tokens render
        # inside the set like anywhere else. Sets nest inside objects, not inside arrays.
        $ResolveAnyOf = {
            param($Node, $Current, $UseCurrent)
            if ($Node -is [System.Collections.IDictionary]) { $Node = [PSCustomObject]$Node }
            if ($Node -isnot [System.Management.Automation.PSCustomObject]) {
                # The comma keeps single-element arrays as arrays - a bare return
                # enumerates them, which flattened ['block'] to 'block' and broke
                # every array-valued expected property.
                if ($Node -is [array]) { return , $Node }
                return $Node
            }
            $Names = @($Node.PSObject.Properties.Name)
            if ($Names.Count -eq 1 -and $Names[0] -eq '$anyOf') {
                $Allowed = @($Node.'$anyOf')
                # Membership is HARD: an empty current value (null/''/[]) only matches an
                # explicit null member, and a boolean member only matches a real boolean.
                $IsMember = @($Allowed | Where-Object {
                        if ($null -eq $Current -or ('' -eq "$Current" -and $Current -isnot [bool])) { $null -eq $_ }
                        elseif ($_ -is [bool]) { $Current -is [bool] -and $_ -eq $Current }
                        else { $null -ne $_ -and $_ -eq $Current }
                    }).Count -gt 0
                if ($UseCurrent -and $IsMember) { return $Current }
                return ($Allowed | Where-Object { $null -ne $_ } | Select-Object -First 1)
            }
            $Resolved = [PSCustomObject]@{}
            foreach ($Property in $Node.PSObject.Properties) {
                $Resolved | Add-Member -NotePropertyName $Property.Name -NotePropertyValue (& $ResolveAnyOf $Property.Value $Current.$($Property.Name) $UseCurrent)
            }
            $Resolved
        }

        # One row per (tenant, standard): RowKey = the sanitized standard name. Rows
        # written under the old '<standard>-<templateId>' keys are self-healed here -
        # the newest state (by LastRun) becomes Prior so triage survives, and every
        # non-canonical sibling is deleted before this run writes the canonical row.
        $PriorRows = @(Get-CIPPAzDataTableEntity @ResolvedTable -Filter "PartitionKey eq '$SafeTenant' and StandardName eq '$SafeStandard'")
        $CanonicalRowKey = $Item.Standard -replace '#', '~'
        $StaleRows = @($PriorRows | Where-Object { $_.RowKey -ne $CanonicalRowKey })
        if ($StaleRows.Count -gt 0) {
            try { Remove-CIPPAzDataTableEntity -Force @ResolvedTable -Entity $StaleRows } catch { Write-Information "Baselines: stale resolved-row cleanup for $($Item.Standard) on $TenantFilter failed: $($_.Exception.Message)" }
        }
        $Prior = $PriorRows | Sort-Object -Property { [int64]($_.LastRun ?? 0) } -Descending | Select-Object -First 1
        $PriorStatus = $Prior.Status
        # Per-property acceptances (design addendum): parsed up front because they shape the
        # compare, the remediation gate, and the resulting status.
        $AcceptedPaths = $(try { $Prior.AcceptedPaths | ConvertFrom-Json } catch { $null })
        $AcceptedKeys = @($AcceptedPaths.PSObject.Properties.Name | Where-Object { $_ })
        # Per-path verdicts: entries default to 'accept' (tolerate); 'denyDelete' marks
        # the path's object for deletion once delete executors exist. Both filter the
        # diff (the operator decided), but deny-delete parks the row at Delete Pending
        # instead of scoring it Accepted.
        $DenyDeleteKeys = @($AcceptedPaths.PSObject.Properties | Where-Object { $_.Name -and $_.Value.verdict -eq 'denyDelete' } | ForEach-Object { $_.Name })
        $ExpectedTemplate = & $Render $Definition.expected $Item.Variables
        $Expected = & $ResolveAnyOf $ExpectedTemplate $null $false
        $Tiers = foreach ($Tier in @($Item.Tiers)) {
            if (-not $Tier) { continue }
            [PSCustomObject]@{
                templateName     = $Tier.templateName
                assignedTo       = $Tier.assignedTo
                # Template-backed (prepare) standards: the rendered declarative expected
                # is just a template reference and misleads - show what the tier
                # CONFIGURES instead; the full expected value lives on the resolved row.
                value            = $(if ($Definition.prepare) { $Tier.variables } else { & $ResolveAnyOf (& $Render $Definition.expected $Tier.variables) $null $false })
                # Action posture per source, so the UI can show WHY two tiers with
                # identical settings still conflict (differing remediate/alert flags).
                remediateEnabled = [bool]$Tier.remediateEnabled
                alertEnabled     = [bool]$Tier.alertEnabled
                alertOnRemediate = [bool]$Tier.alertOnRemediate
                effective        = [bool]$Tier.effective
            }
        }

        $Result = [PSCustomObject]@{
            Item                = $Item
            Mode                = $Mode
            TriggeredBy         = $TriggeredBy
            ExpectedValue       = $Expected
            CurrentValue        = $null
            Compliant           = $false
            PendingVerification = $false
            LicenseAvailable    = $true
            Status              = $PriorStatus
            Remediated          = $false
            Outcome             = 'Error'
            Diff                = $null
            # RowDiff = the PRE-acceptance per-property deviations, persisted on the
            # resolved row so the frontend renders the ENGINE's verdict per property -
            # it never re-derives compares (single source of truth). Accepted-path
            # tolerated properties stay listed; the UI dims them via acceptedPaths.
            RowDiff             = @()
            # The rendered manual block (taskName/instructions/documentationUrl/reopen)
            # persists on the resolved row so the offcanvas can show the operator what
            # to actually do.
            Manual              = $null
            Inheritance         = @($Tiers)
            AlertEvent          = $null
            CacheType           = $Definition.read.cacheType
        }

        # 1b0. Conflict: two baselines configure this identity at the same level with
        # different settings, so even the expected value is ambiguous - nothing is
        # compared, nothing is written to the tenant. The row parks at 'Conflict' (with
        # every colliding source in its inheritance tiers) until an operator changes one
        # of the baselines. Alerts fire on the transition in.
        if ($Item.Conflicted -eq $true) {
            $Result.ExpectedValue = $null
            $Result.Outcome = 'Conflict'
            $Result.Status = 'Conflict'
            Write-LogMessage -API 'Baselines' -tenant $TenantFilter -message "Conflict: `"$Label`" is configured with different settings at the same level by $(@($Item.ConflictWith) -join ' and ') - nothing runs until one of them changes. - Run $RunId" -Sev 'Warning'
            if ($PriorStatus -ne 'Conflict' -and $Item.AlertEnabled) { $Result.AlertEvent = 'Conflict' }
            Set-CIPPBaselineResult -Result $Result -Prior $Prior -RunId $RunId
            if ($Result.AlertEvent) { Send-CIPPBaselineAlert -Result $Result }
            return $Result
        }

        # 1b. Manual tasks: state lives on the resolved row; the operator completes them.
        if ($Definition.manual) {
            $Manual = & $Render $Definition.manual $Item.Variables
            $Result.Manual = $Manual
            $Completed = [bool]($(try { $Prior.CurrentValue | ConvertFrom-Json } catch { $null })?.completed)
            $LastDone = if ("$($Prior.LastRemediated)" -match '^\d+$') { [int64]$Prior.LastRemediated } else { 0 }
            $ReopenSeconds = switch ($Manual.reopen) {
                'weekly' { 7 * 86400 }
                'monthly' { 30 * 86400 }
                'quarterly' { 91 * 86400 }
                default { 0 } # once - never reopens
            }
            if ($Completed -and $ReopenSeconds -gt 0 -and $LastDone -gt 0 -and $Now -ge ($LastDone + $ReopenSeconds)) {
                $Completed = $false # the recurrence elapsed - the task is due again
            }
            $Result.CurrentValue = [PSCustomObject]@{ completed = $Completed }
            $Result.Compliant = $Completed
            if (-not $Completed) {
                $Result.RowDiff = @([PSCustomObject]@{ Property = 'completed'; ExpectedValue = $true; ReceivedValue = $false })
            }
            $Result.Outcome = if ($Completed) { 'Compliant' } else { 'Drift' }
            $Result.Status = if ($Completed) { 'Compliant' } elseif ($PriorStatus -eq 'Accepted') { 'Accepted' } else { 'Drift' }
            if ($Result.Status -eq 'Drift' -and $PriorStatus -ne 'Drift' -and $Item.AlertEnabled) {
                $Result.AlertEvent = 'Drift'
            }
            Set-CIPPBaselineResult -Result $Result -Prior $Prior -RunId $RunId
            if ($Result.AlertEvent) { Send-CIPPBaselineAlert -Result $Result }
            return $Result
        }

        # 2. Read the current value from CIPPDb. On a miss, trigger the central collector for
        # this cacheType and re-read once - a new standard must be able to run on its first
        # pass instead of skipping forever.
        $ReadCurrent = {
            $Data = @(New-CIPPDbRequest -TenantFilter $TenantFilter -Type $Definition.read.cacheType | Where-Object { $_ })
            # read.array (a dot-path) descends into each cached row's nested array and
            # flattens the elements into the candidate set BEFORE the filters run, so a
            # definition can select e.g. one entry of authenticationMethodConfigurations
            # declaratively.
            if ($Definition.read.array) {
                $Data = @($Data | ForEach-Object {
                        $Nested = $_
                        foreach ($Segment in ($Definition.read.array -split '\.')) { $Nested = $Nested.$Segment }
                        $Nested
                    } | Where-Object { $_ })
            }
            foreach ($Condition in @($Definition.read.filter)) {
                if (-not $Condition) { continue }
                $Match = & $Render $Condition.value $Item.Variables
                $Property = $Condition.property
                $Data = @($Data | Where-Object {
                        # filter.property may itself be a dot-path into the candidate.
                        $Candidate = $_
                        foreach ($Segment in ($Property -split '\.')) { $Candidate = $Candidate.$Segment }
                        switch ($Condition.operator) {
                            'ne' { $Candidate -ne $Match }
                            'startsWith' { "$Candidate".StartsWith("$Match") }
                            'notStartsWith' { -not "$Candidate".StartsWith("$Match") }
                            default { $Candidate -eq $Match }
                        }
                    })
            }
            $Value = $Data | Select-Object -First 1
            if ($Definition.read.object -and $null -ne $Value) {
                foreach ($Segment in ($Definition.read.object -split '\.')) {
                    $Value = $Value.$Segment
                }
            }
            $Value
        }
        # Pre-check gate, for TEMPLATE standards only (prepare hook = CA/Intune): their
        # verdicts drive policy deploys and their domains change under external hands.
        # Wait-CIPPBaselineCacheReady verifies the cache is complete (all required
        # family caches collected), recent (3h), and consistent with live state (CA
        # live-count probe) - and enforces SINGLE-FLIGHT collection: one job per
        # (tenant, cacheType) collects while every parallel peer waits, so activities
        # never compare against a half-written cache and users never get race alerts.
        # Everything else tolerates normal CIPPDb cadence staleness.
        $JustRefreshed = $false
        $CacheCollector = Get-Command -Name "Set-CIPPDBCache$($Definition.read.cacheType)" -ErrorAction SilentlyContinue
        if ($CacheCollector -and $Definition.prepare) {
            $JustRefreshed = Wait-CIPPBaselineCacheReady -TenantFilter $TenantFilter -Definition $Definition -RunId $RunId
        }

        if ($Definition.prepare) {
            # Prepare hook: complex standards (CA/Intune templates) produce their own
            # NORMALIZED Expected/Current pair - both sides translated to one canonical
            # vocabulary from CIPPDb caches only. The engine still owns everything else:
            # compare, hard gaps, accepted paths, triage, conflict, remediation and
            # persistence. Collector-on-miss applies exactly like the declarative read.
            $PrepareFunction = Get-Command -Name $Definition.prepare -ErrorAction SilentlyContinue
            if (-not $PrepareFunction) { throw "Prepare function $($Definition.prepare) is not available." }
            $Prepared = & $Definition.prepare -Item $Item -TenantFilter $TenantFilter
            if ($null -eq $Prepared.Current -and $CacheCollector -and -not $JustRefreshed) {
                try {
                    $null = & $CacheCollector -TenantFilter $TenantFilter
                    $Prepared = & $Definition.prepare -Item $Item -TenantFilter $TenantFilter
                } catch {
                    Write-Information "Baselines: cache collection for $($Definition.read.cacheType) on $TenantFilter failed: $($_.Exception.Message)"
                }
            }
            if ($null -ne $Prepared.Expected) {
                $ExpectedTemplate = $Prepared.Expected
                $Expected = $Prepared.Expected
                $Result.ExpectedValue = $Expected
            }
            # Fail-safe against poisoned-empty caches: when the WHOLE policy family came
            # back empty but this policy was observed live within the last 7 days, a
            # failed or flaky collection (Graph intermittently returns empty collections)
            # is far more likely than a mass deletion. Report No Data and retry instead
            # of declaring every policy missing and fanning out false drift/deploys. A
            # genuinely emptied family resumes drifting once the hold ages out (skips
            # never advance LastRun).
            if ($Prepared.EmptyFamily) {
                # 'Seen live' means the prior current state carried actual policy data -
                # not the missing-policy marker, and not the marker's all-null projection.
                $PriorCurrentParsed = $(try { $Prior.CurrentValue | ConvertFrom-Json -ErrorAction Stop } catch { $null })
                $PriorHadLiveData = if ($PriorCurrentParsed -is [System.Management.Automation.PSCustomObject]) {
                    (-not $PriorCurrentParsed.PSObject.Properties['policyStatus']) -and
                    @($PriorCurrentParsed.PSObject.Properties | Where-Object { $null -ne $_.Value }).Count -gt 0
                } else { $null -ne $PriorCurrentParsed }
                $PriorSawPolicy = $PriorHadLiveData -and
                ([int64]($Prior.LastRun ?? 0) -gt ([DateTimeOffset]::UtcNow.ToUnixTimeSeconds() - 604800))
                if ($PriorSawPolicy) {
                    Write-LogMessage -API 'Baselines' -tenant $TenantFilter -message "$($Item.Standard): the $($Definition.read.cacheType) family cache is empty but this policy was live recently - treating as No Data (suspected collection failure), retrying next run." -Sev 'Warning'
                    $Result.Outcome = 'Skipped-NoCache'
                    $Result.Status = $PriorStatus ?? 'No Data'
                    return $Result
                }
            }
            $Current = $Prepared.Current
        } else {
            $Current = & $ReadCurrent
            if ($null -eq $Current -and $CacheCollector -and -not $JustRefreshed) {
                try {
                    $null = & $CacheCollector -TenantFilter $TenantFilter
                    $Current = & $ReadCurrent
                } catch {
                    Write-Information "Baselines: cache collection for $($Definition.read.cacheType) on $TenantFilter failed: $($_.Exception.Message)"
                }
            }
        }

        # checkBeforeRun=false marks standards whose pre-check cannot prove the write is
        # unnecessary (e.g. a CA template compare only sees name/state) - they write whenever
        # remediation applies, cache or not. A missing cache does NOT return early: the
        # engine fails OPEN - when the current state cannot be read, an enforced standard
        # still applies its expected state, and only a compare/report-only run skips.
        $CheckBeforeRun = $Definition.checkBeforeRun -ne $false

        # 3. Project to the expected keys (subset compare) and diff. A key the current object
        # lacks stays present as $null so the compare flags the presence mismatch.
        $Differences = @()
        $PreFilterDifferences = @()
        if ($null -ne $Current) {
            $Projected = [PSCustomObject]@{}
            foreach ($Property in $Expected.PSObject.Properties.Name) {
                $Projected | Add-Member -NotePropertyName $Property -NotePropertyValue $Current.$Property
            }
            $Result.CurrentValue = $Projected
            # The compare copy of expected resolves $anyOf against the CURRENT value: a
            # member of the set compares equal, a non-member diffs against the canonical.
            $CompareExpected = & $ResolveAnyOf $ExpectedTemplate $Current $true
            # Compare-CIPPIntuneObject emits $null (not an empty set) when nothing differs.
            # A prepare hook may request a CompareType (e.g. 'Catalog' flattens settings
            # catalog policies to per-setting rows, 'AppProtection' widens the excludes).
            $CompareTypes = @($Prepared.CompareType | Where-Object { $_ })
            $Differences = @(Compare-CIPPIntuneObject -ReferenceObject $CompareExpected -DifferenceObject $Projected -CompareType $CompareTypes | Where-Object { $_ })

            # Hard compares: the shared compare treats false/0/null/''/[] as interchangeable
            # empties, which would let 'not configured' satisfy an explicit false/0
            # expectation. The shared function stays untouched (CA/Intune depend on its
            # semantics) - this only ADDS the diffs the engine's stricter reading requires:
            # an expected boolean or number against an empty current value is drift.
            # Definition-controlled via `hardCompare` (default ON; the CA/Intune template
            # definitions set false - their prepare pipelines carry their own extensive
            # normalization and the lenient empties-equivalence is load-bearing there).
            # Two boundaries when enabled: properties the compare deliberately excludes
            # (read-only server state like qualityUpdatesWillBeRolledBack) are never
            # hard-gapped - same list, one source; and flatten-based Catalog compares
            # skip the walker entirely (their paths don't align with the raw tree).
            $HardCompareEnabled = $Definition.hardCompare -ne $false
            $HardGapExclusions = @(Get-CIPPIntuneCompareExclusions -AppProtection:($CompareTypes -contains 'AppProtection'))
            $AddHardGaps = $null
            $AddHardGaps = {
                param($ExpectedNode, $CurrentNode, $Prefix, $Gaps)
                foreach ($ExpectedProperty in ($ExpectedNode ?? [PSCustomObject]@{}).PSObject.Properties) {
                    if ($HardGapExclusions -contains $ExpectedProperty.Name -or $ExpectedProperty.Name -like '*@OData*' -or $ExpectedProperty.Name -like '#microsoft.graph*') { continue }
                    $Path = if ($Prefix) { '{0}.{1}' -f $Prefix, $ExpectedProperty.Name } else { $ExpectedProperty.Name }
                    $ExpectedLeaf = $ExpectedProperty.Value
                    $CurrentLeaf = if ($null -ne $CurrentNode) { $CurrentNode.$($ExpectedProperty.Name) } else { $null }
                    if ($ExpectedLeaf -is [System.Management.Automation.PSCustomObject]) {
                        & $AddHardGaps $ExpectedLeaf $CurrentLeaf $Path $Gaps
                    } elseif ($ExpectedLeaf -is [bool] -or $ExpectedLeaf -is [int] -or $ExpectedLeaf -is [int64] -or $ExpectedLeaf -is [double] -or $ExpectedLeaf -is [decimal]) {
                        if ($null -eq $CurrentLeaf -or ('' -eq "$CurrentLeaf" -and $CurrentLeaf -isnot [bool])) {
                            $Gaps.Add([PSCustomObject]@{ Property = $Path; ExpectedValue = $ExpectedLeaf; ReceivedValue = $CurrentLeaf })
                        }
                    }
                }
            }
            # StrictCompare: properties a prepare declares as always-compared, exact and
            # type-strict, regardless of compare type (e.g. isAssigned - the Catalog
            # flatten only sees settings arrays and would silently ignore it).
            foreach ($StrictProperty in @($Prepared.StrictCompare | Where-Object { $_ })) {
                $ExpectedStrict = $CompareExpected.$StrictProperty
                $CurrentStrict = $Projected.$StrictProperty
                if ("$ExpectedStrict" -ne "$CurrentStrict" -and @($Differences | Where-Object { $_.Property -eq $StrictProperty }).Count -eq 0) {
                    $Differences = @($Differences) + @([PSCustomObject]@{ Property = $StrictProperty; ExpectedValue = $ExpectedStrict; ReceivedValue = $CurrentStrict })
                }
            }

            $HardGaps = [System.Collections.Generic.List[object]]::new()
            if ($HardCompareEnabled -and $CompareTypes -notcontains 'Catalog') {
                & $AddHardGaps $CompareExpected $Projected '' $HardGaps
            }
            if ($HardGaps.Count -gt 0) {
                $Merged = [System.Collections.Generic.List[object]]::new()
                foreach ($Difference in $Differences) { $Merged.Add($Difference) }
                foreach ($Gap in $HardGaps) {
                    if (@($Differences | Where-Object { $_.Property -eq $Gap.Property }).Count -eq 0) { $Merged.Add($Gap) }
                }
                $Differences = @($Merged)
            }

            # An accepted path tolerates that property's drift - and only that property's.
            # Prefix matches cover nested paths.
            $PreFilterDifferences = $Differences
            if ($AcceptedKeys.Count -gt 0) {
                $Differences = @($Differences | Where-Object {
                        $Property = $_.Property
                        -not ($AcceptedKeys | Where-Object { $Property -eq $_ -or $Property.StartsWith("$_.") })
                    })
            }
            $Result.Diff = $Differences
            $Result.RowDiff = $PreFilterDifferences
        }
        $Compliant = ($null -ne $Current) -and ($Differences.Count -eq 0)
        # True when accepted paths actually swallowed drift this run - the row's alignment
        # (full or partial) is owed to acceptances, not to the tenant matching the baseline.
        $PathAccepted = $PreFilterDifferences.Count -gt $Differences.Count

        if ($Mode -ne 'compare' -and $Definition.delete -and $DenyDeleteKeys.Count -gt 0 -and $null -ne $Current) {
            $DeletedKeys = [System.Collections.Generic.List[string]]::new()
            foreach ($DenyKey in $DenyDeleteKeys) {
                $Target = $Current.$DenyKey
                # No target means the object is already gone from the tenant - the
                # verdict is stale, drop it rather than calling Graph.
                if (-not $Target -or -not "$($Target.id)") {
                    $DeletedKeys.Add($DenyKey)
                    continue
                }
                # The verdict author is the accountable party - captured before the
                # carried-out verdict is cleared, and stamped on the audit event.
                $VerdictBy = "$($AcceptedPaths.$DenyKey.by)"
                try {
                    switch ($Definition.delete.executor) {
                        'IntunePolicy' { Invoke-CIPPBaselineDeleteIntunePolicy -Target $Target -TenantFilter $TenantFilter }
                        'CAPolicy' { Invoke-CIPPBaselineDeleteCAPolicy -Target $Target -TenantFilter $TenantFilter }
                        default { throw "Unknown delete executor '$($Definition.delete.executor)' on $($Definition.name)." }
                    }
                    $DeletedKeys.Add($DenyKey)
                    Write-LogMessage -API 'Baselines' -tenant $TenantFilter -message "Deleted `"$DenyKey`" for `"$Label`" as ordered by the denied deviation - Run $RunId" -Sev 'Info'
                    # A deletion is irreversible: it gets its own immutable history event
                    # naming the object AND who ordered it, not just Remediated=true.
                    $null = Add-CIPPBaselineHistoryEvent -TenantFilter $TenantFilter -Standard $Item.Standard -Mode 'delete' -TriggeredBy ($VerdictBy ? $VerdictBy : $TriggeredBy) -Outcome 'Deleted' -Detail "Deleted '$DenyKey' (id $($Target.id)) as ordered by the denied deviation" -RunId $RunId -Remediated $true
                } catch {
                    Write-LogMessage -API 'Baselines' -tenant $TenantFilter -message "Failed to delete `"$DenyKey`" for `"$Label`": $($_.Exception.Message) - Run $RunId" -Sev 'Error'
                    $null = Add-CIPPBaselineHistoryEvent -TenantFilter $TenantFilter -Standard $Item.Standard -Mode 'delete' -TriggeredBy ($VerdictBy ? $VerdictBy : $TriggeredBy) -Outcome 'Delete Failed' -Detail "Failed to delete '$DenyKey': $($_.Exception.Message)" -RunId $RunId
                }
            }
            if ($DeletedKeys.Count -gt 0) {
                foreach ($DeletedKey in $DeletedKeys) { $AcceptedPaths.PSObject.Properties.Remove($DeletedKey) }
                $AcceptedKeys = @($AcceptedPaths.PSObject.Properties.Name | Where-Object { $_ })
                $DenyDeleteKeys = @($AcceptedPaths.PSObject.Properties | Where-Object { $_.Name -and $_.Value.verdict -eq 'denyDelete' } | ForEach-Object { $_.Name })
                 if ($Prior) { $Prior | Add-Member -NotePropertyName 'AcceptedPaths' -NotePropertyValue (ConvertTo-Json -Compress -Depth 20 -InputObject $AcceptedPaths) -Force }
                 $DropDeleted = {
                    param($Entries)
                    @($Entries | Where-Object {
                            $Property = $_.Property
                            -not ($DeletedKeys | Where-Object { $Property -eq $_ -or $Property.StartsWith("$_.") })
                        })
                }
                $PreFilterDifferences = & $DropDeleted $PreFilterDifferences
                $Differences = & $DropDeleted $Differences
                $Result.Diff = $Differences
                $Result.RowDiff = $PreFilterDifferences
                $Result.Remediated = $true
                $Compliant = ($Differences.Count -eq 0)
                $PathAccepted = $PreFilterDifferences.Count -gt $Differences.Count
                   if ($DenyDeleteKeys.Count -eq 0 -and $PriorStatus -eq 'Denied - Delete Pending') { $PriorStatus = 'Drift' }
            }
        }

        # 4. Status lifecycle + write gate.
        $Expires = if ("$($Prior.DeviationExpires)" -match '^\d+$') { [int64]$Prior.DeviationExpires } else { 0 }
        $AcceptActive = $PriorStatus -eq 'Accepted' -and ($Expires -eq 0 -or $Now -lt $Expires)
        $RemediateOnExpire = $PriorStatus -eq 'Accepted' -and $Expires -gt 0 -and $Now -ge $Expires -and [bool]$Prior.RemediateOnExpire
        # A denied deviation is an operator order: remediate regardless of the configured posture.
        $DeniedRemediate = $PriorStatus -eq 'Denied - Remediate Pending'

        if (-not $Compliant -and $null -ne $Current -and $AcceptActive) {
            # Tolerated: no remediation, no alert; Accepted counts aligned (shown as inflating).
            $Result.Outcome = 'Drift'
            $Result.Status = 'Accepted'
            Set-CIPPBaselineResult -Result $Result -Prior $Prior -RunId $RunId
            return $Result
        }
        if (-not $Compliant -and $null -ne $Current -and $PriorStatus -eq 'Denied - Delete Pending') {
            # Held: either a ROW-level deny (which never bulk-deletes - deletion is a
            # per-object decision, so it waits for per-path verdicts), or a per-path
            # verdict whose delete failed this run. Both retry on the next run.
            $Result.Outcome = 'Drift'
            $Result.Status = 'Denied - Delete Pending'
            Set-CIPPBaselineResult -Result $Result -Prior $Prior -RunId $RunId
            return $Result
        }
        if ($Compliant -and $PathAccepted -and $PriorStatus -ne 'Denied - Remediate Pending') {
            # Aligned only because every deviating property is individually triaged: all
            # accepts score as Accepted (aligned via acceptance, not compliance); any
            # deny-delete verdict with live drift parks the row at Delete Pending until
            # delete executors exist. The tolerated diff stays visible in history.
            $DenyDeleteLive = $DenyDeleteKeys.Count -gt 0 -and @($PreFilterDifferences | Where-Object {
                    $Property = $_.Property
                    $DenyDeleteKeys | Where-Object { $Property -eq $_ -or $Property.StartsWith("$_.") }
                }).Count -gt 0
            $Result.Diff = $PreFilterDifferences
            $Result.Outcome = 'Drift'
            $Result.Status = $(if ($DenyDeleteLive) { 'Denied - Delete Pending' } else { 'Accepted' })
            Set-CIPPBaselineResult -Result $Result -Prior $Prior -RunId $RunId
            return $Result
        }

        # An active Accept, a pending delete, or a live path acceptance always blocks
        # remediation - including the fail-open path. Remediation writes the WHOLE expected
        # object, which would wipe an accepted property's deviation along with the rest.
        $PathHold = $AcceptedKeys.Count -gt 0 -and ($PathAccepted -or $null -eq $Current)
        $TriageHold = $AcceptActive -or $PriorStatus -eq 'Denied - Delete Pending' -or $PathHold
        $RemediationAllowed = (($Mode -eq 'oneoff') -or ($Mode -eq 'run' -and ($Item.RemediateEnabled -or $RemediateOnExpire -or $DeniedRemediate))) -and -not $TriageHold
        # Write only when needed: drift proves it, -Force (manual runs) demands it, and
        # checkBeforeRun=false standards cannot prove a write unnecessary.
        $WriteNeeded = (-not $Compliant) -or $Force.IsPresent -or (-not $CheckBeforeRun)

        # Detect standards carry no remediate executor by design - they are report-only
        # tripwires; deletion happens only via explicit per-path deny verdicts.
        if ($Mode -ne 'compare' -and $RemediationAllowed -and $WriteNeeded -and $Definition.remediate) {
            $ExpectedJson = ConvertTo-Json -Compress -Depth 100 -InputObject $Expected
            try {
                $Rendered = & $Render $Definition.remediate $Item.Variables
                switch ($Definition.remediate.executor) {
                    'ExoRequest' { Invoke-CIPPBaselineExoRequest -Remediate $Rendered -TenantFilter $TenantFilter }
                    'GraphRequest' { Invoke-CIPPBaselineGraphRequest -Remediate $Rendered -TenantFilter $TenantFilter }
                    'TeamsRequest' { Invoke-CIPPBaselineTeamsRequest -Remediate $Rendered -TenantFilter $TenantFilter }
                    'SPOTenant' { Invoke-CIPPBaselineSPOTenant -Remediate $Rendered -TenantFilter $TenantFilter }
                    'CATemplate' { Invoke-CIPPBaselineCATemplate -Remediate $Rendered -TenantFilter $TenantFilter }
                    'IntuneTemplate' { Invoke-CIPPBaselineIntuneTemplate -Remediate $Rendered -TenantFilter $TenantFilter }
                    default { throw "Unknown remediate executor '$($Definition.remediate.executor)' on $($Definition.name)." }
                }
            } catch {
                Write-LogMessage -API 'Baselines' -tenant $TenantFilter -message "Failed to change `"$Label`" to $ExpectedJson`: $($_.Exception.Message) - Run $RunId" -Sev 'Error'
                $Result.Outcome = 'Error'
                Set-CIPPBaselineResult -Result $Result -Prior $Prior -RunId $RunId
                return $Result
            }
            Write-LogMessage -API 'Baselines' -tenant $TenantFilter -message "Successfully changed `"$Label`" to $ExpectedJson - Run $RunId" -Sev 'Info'
            # Optimistic post-write: currentValue = what we wrote; the next run's cache read verifies.
            $Result.CurrentValue = $Expected
            $Result.Compliant = $true
            $Result.RowDiff = @()
            $Result.PendingVerification = $true
            $Result.Remediated = $true
            $Result.Outcome = 'Remediated'
            $Result.Status = 'Compliant'
            if ($Item.AlertOnRemediate) { $Result.AlertEvent = 'Remediated' }
        } elseif ($Compliant) {
            $Result.Compliant = $true
            $Result.Outcome = 'Compliant'
            $Result.Status = 'Compliant'
        } elseif ($null -eq $Current) {
            # No cache and remediation does not apply (compare mode / report-only): there is
            # nothing to honestly report, so nothing is written - the row stays 'No Data'
            # and retries next run.
            Write-LogMessage -API 'Baselines' -tenant $TenantFilter -message "$($Item.Standard): no $($Definition.read.cacheType) data in CIPPDb after collection and remediation does not apply - skipped, nothing written." -Sev 'Info'
            $Result.Outcome = 'Skipped-NoCache'
            $Result.Status = $PriorStatus ?? 'No Data'
            return $Result
        } else {
            $Result.Outcome = 'Drift'
            # A pending deny is an operator order - a run that could not remediate (compare
            # mode, or a failed attempt) must not silently clear it. Drift partially covered
            # by accepted paths surfaces as Partially Accepted.
            $Result.Status = if ("$PriorStatus".StartsWith('Denied')) { $PriorStatus } elseif ($PathAccepted) { 'Partially Accepted' } else { 'Drift' }
            # Alerts fire on the transition INTO drift (full or partial), not every run.
            if ($Result.Status -in @('Drift', 'Partially Accepted') -and $PriorStatus -notin @('Drift', 'Partially Accepted') -and $Item.AlertEnabled) { $Result.AlertEvent = 'Drift' }
        }

        Set-CIPPBaselineResult -Result $Result -Prior $Prior -RunId $RunId
        if ($Result.AlertEvent) { Send-CIPPBaselineAlert -Result $Result }
        return $Result
    } catch {
        Write-LogMessage -API 'Baselines' -tenant $TenantFilter -message "Baseline run failed for $($Item.Standard) on ${TenantFilter}: $($_.Exception.Message)" -Sev 'Error'
        if ($Result) {
            $Result.Outcome = 'Error'
            try { Set-CIPPBaselineResult -Result $Result -Prior $Prior -RunId $RunId } catch { Write-Information "Set-CIPPBaselineResult failed: $($_.Exception.Message)" }
            return $Result
        }
    }
}
