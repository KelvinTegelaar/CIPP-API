function Invoke-CIPPBaselineStandard {
    <#
    .SYNOPSIS
        Runs one standard instance against one tenant: read, compare, triage, remediate, persist.
    .DESCRIPTION
        The engine for a single (tenant, standard) work item from Get-CIPPBaselineWorkItems.
        Licensing is handled upstream by Start-CIPPBaselineOrchestrator. Work items arrive
        through the durable pipeline as Hashtables, so item-derived values are normalized
        before use.

        There is ONE flow. A standard whose read or write cannot be expressed declaratively
        replaces THAT PART ONLY - a prepare hook for the read, a named executor for the
        write - and the engine still owns compare, hard gaps, accepted paths, triage,
        conflict, deletion and persistence. Both are resolved by naming convention, so
        adding either never touches this file:
            remediate.executor 'Foo' -> Invoke-CIPPBaselineFoo
            delete.executor    'Foo' -> Invoke-CIPPBaselineDeleteFoo
            prepare                  -> the Get-CIPPBaseline*State function it names

        -GradeOnly is the post-remediation cache verification: read and compare only,
        returning { Compliant, CurrentValue, Diff } while persisting NOTHING - no history
        events, no alignment writes, no alerts, no remediation. Only meaningful right after
        a remediation on the same item, where conflict/unconfigured/manual cannot occur.
    .FUNCTIONALITY
        Internal
    #>
    [CmdletBinding()]
    param(
        $Item,
        [ValidateSet('run', 'compare', 'oneoff')]$Mode = 'run',
        $TriggeredBy = 'schedule',
        [switch]$Force,
        [switch]$GradeOnly,
        $RunId
    )
    if (-not $RunId) { $RunId = [string](New-Guid).Guid }

    $TenantFilter = $Item.TenantFilter
    $Now = [int64]([datetimeoffset]::UtcNow.ToUnixTimeSeconds())

    # Splices variable values into the serialized template. A key whose value is exactly the
    # "%var%" token keeps its JSON type; omitWhenBlank drops such a key entirely so expected
    # and remediate specs stay consistent. Tenant tokens resolve last.
    $Render = {
        param($Template, $Variables)
        if ($null -eq $Template) { return $null }
        if ($Variables -is [System.Collections.IDictionary]) { $Variables = [PSCustomObject]$Variables }
        $Json = ConvertTo-Json -Compress -Depth 100 -InputObject $Template
        foreach ($Declared in (($Definition.variables ?? [PSCustomObject]@{}).PSObject.Properties)) {
            if ($Declared.Value.omitWhenBlank -ne $true) { continue }
            if (-not [string]::IsNullOrEmpty("$(($Variables ?? [PSCustomObject]@{}).($Declared.Name))")) { continue }
            $Escaped = [regex]::Escape(('%{0}%' -f $Declared.Name))
            $Json = [regex]::Replace($Json, ('"[^"]*":"{0}",' -f $Escaped), '')
            $Json = [regex]::Replace($Json, (',"[^"]*":"{0}"' -f $Escaped), '')
            $Json = [regex]::Replace($Json, ('"[^"]*":"{0}"' -f $Escaped), '')
        }
        foreach ($Variable in (($Variables ?? [PSCustomObject]@{}).PSObject.Properties)) {
            $Token = '%{0}%' -f $Variable.Name
            $Value = $Variable.Value
            # A number field is saved as a STRING ("30", not 30) - the frontend posts what the
            # input holds. Splicing that into an exact "%var%" token yields a JSON string, and
            # the compare is type-strict: expected "50" never equals a cached 50, so the
            # standard reports drift forever and remediation writes the string back. Coerce on
            # the DECLARED type so already-saved baselines are fixed too, not just new ones.
            if ("$(($Definition.variables ?? [PSCustomObject]@{}).($Variable.Name).type)" -eq 'number' -and
                $Value -is [string] -and "$Value" -match '^-?\d+(\.\d+)?$') {
                $Value = if ("$Value" -match '^-?\d+$') { [int64]"$Value" } else { [double]"$Value" }
            }
            $EncodedValue = ConvertTo-Json -Compress -Depth 100 -InputObject $Value
            $Json = $Json.Replace(('"{0}"' -f $Token), $EncodedValue)
            $Json = $Json.Replace($Token, "$Value")
        }
        $Json = Get-CIPPTextReplacement -TenantFilter $TenantFilter -Text $Json -EscapeForJson
        $Json | ConvertFrom-Json
    }

    try {
        $Definition = Get-CIPPBaselineDefinition -Name $Item.BaseName
        if (-not $Definition) { throw "No definition found for standard $($Item.BaseName)." }
        if ($Definition.package) { throw "Package standard $($Item.BaseName) must be expanded by the resolver and never executes directly." }
        $Label = $Definition.label ?? $Item.Standard

        # A flat requiredCapabilities list is any-of; a nested array is a group that must
        # also match (AND of any-of groups).
        $Required = @($Definition.requiredCapabilities)
        if ($Required.Count -gt 0 -and $Mode -ne 'oneoff') {
            $Capabilities = $(try { Get-CIPPTenantCapabilities -TenantFilter $TenantFilter } catch { $null })
            # Built as a List: an if-expression's pipeline output unwraps one array level,
            # which silently turned every capability into its own AND-group.
            $Groups = [System.Collections.Generic.List[object]]::new()
            if (@($Required | Where-Object { $_ -is [System.Array] }).Count -gt 0) {
                foreach ($Entry in $Required) { $Groups.Add(@($Entry)) }
            } else {
                $Groups.Add(@($Required))
            }
            $Licensed = $true
            foreach ($Group in $Groups) {
                if (@(@($Group) | Where-Object { $Capabilities.$_ -eq $true }).Count -eq 0) {
                    $Licensed = $false
                    break
                }
            }
            if (-not $Licensed) {
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

        if (-not $GradeOnly) {
            Write-LogMessage -API 'Baselines' -tenant $TenantFilter -message "Started `"$Label`" ($Mode) - Run $RunId" -Sev 'Info'
        }

        $ResolvedTable = Get-CippTable -tablename 'BaselineAlignment'
        $SafeTenant = ConvertTo-CIPPODataFilterValue -Value $TenantFilter
        $SafeStandard = ConvertTo-CIPPODataFilterValue -Value $Item.Standard

        # $anyOf: an expected property may declare several acceptable values, e.g.
        # { "$anyOf": ["migrationComplete", null] }. With -UseCurrent a current value inside
        # the set resolves to itself so the compare matches; everywhere the value is
        # displayed or deployed, the first non-null entry is canonical. Membership is HARD:
        # an empty current only matches an explicit null, a boolean only a real boolean.
        $ResolveAnyOf = {
            param($Node, $Current, $UseCurrent)
            if ($Node -is [System.Collections.IDictionary]) { $Node = [PSCustomObject]$Node }
            if ($Node -isnot [System.Management.Automation.PSCustomObject]) {
                # The comma keeps single-element arrays as arrays - a bare return enumerates
                # them, which flattened ['block'] to 'block'.
                if ($Node -is [array]) { return , $Node }
                return $Node
            }
            $Names = @($Node.PSObject.Properties.Name)
            if ($Names.Count -eq 1 -and $Names[0] -eq '$anyOf') {
                $Allowed = @($Node.'$anyOf')
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

        # One row per (tenant, standard). Rows written under the old '<standard>-<templateId>'
        # keys are self-healed: newest by LastRun becomes Prior, siblings are deleted.
        $PriorRows = @(Get-CIPPAzDataTableEntity @ResolvedTable -Filter "PartitionKey eq '$SafeTenant' and StandardName eq '$SafeStandard'")
        $CanonicalRowKey = $Item.Standard -replace '#', '~'
        $StaleRows = @($PriorRows | Where-Object { $_.RowKey -ne $CanonicalRowKey })
        if ($StaleRows.Count -gt 0 -and -not $GradeOnly) {
            try { Remove-CIPPAzDataTableEntity -Force @ResolvedTable -Entity $StaleRows } catch { Write-Information "Baselines: stale resolved-row cleanup for $($Item.Standard) on $TenantFilter failed: $($_.Exception.Message)" }
        }
        $Prior = $PriorRows | Sort-Object -Property { [int64]($_.LastRun ?? 0) } -Descending | Select-Object -First 1
        $PriorStatus = $Prior.Status

        # Per-property verdicts default to 'accept' (tolerate); 'denyDelete' marks the path's
        # object for deletion. Both filter the diff; deny-delete parks the row at Delete
        # Pending instead of scoring it Accepted.
        $AcceptedPaths = $(try { $Prior.AcceptedPaths | ConvertFrom-Json } catch { $null })
        $AcceptedKeys = @($AcceptedPaths.PSObject.Properties.Name | Where-Object { $_ })
        $DenyDeleteKeys = @($AcceptedPaths.PSObject.Properties | Where-Object { $_.Name -and $_.Value.verdict -eq 'denyDelete' } | ForEach-Object { $_.Name })
        $ExpectedTemplate = & $Render $Definition.expected $Item.Variables
        $Expected = & $ResolveAnyOf $ExpectedTemplate $null $false
        $Tiers = foreach ($Tier in @($Item.Tiers)) {
            if (-not $Tier) { continue }
            [PSCustomObject]@{
                templateName     = $Tier.templateName
                assignedTo       = $Tier.assignedTo
                # For prepare-backed standards the rendered expected is just a template
                # reference, so show what the tier CONFIGURES instead.
                value            = $(if ($Definition.prepare) { $Tier.variables } else { & $ResolveAnyOf (& $Render $Definition.expected $Tier.variables) $null $false })
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
            # Pre-acceptance per-property deviations. The frontend renders these verbatim
            # rather than re-deriving compares, so a custom flow that omits it shows an
            # empty property list on a drifted row.
            RowDiff             = @()
            Manual              = $null
            Inheritance         = @($Tiers)
            AlertEvent          = $null
            # ALL declared read caches, not just the primary: a standard whose executor
            # writes to a secondary cache's object (an outbound connector under an inbound
            # read.cacheType, a dynamic distro under Groups) would otherwise leave that
            # cache stale after remediation, and the stale cache re-detects the fixed
            # drift FOREVER - collect-on-miss never fires on collected-and-empty.
            CacheType           = @(@($Definition.read.requiredCaches) + @($Definition.read.cacheType) | Where-Object { $_ } | Sort-Object -Unique)
        }

        # Two baselines configure this identity at the same level with different settings, so
        # even the expected value is ambiguous: nothing is compared, nothing is written.
        if ($Item.Conflicted -eq $true) {
            if ($GradeOnly) { return $null }
            $Result.ExpectedValue = $null
            $Result.Outcome = 'Conflict'
            $Result.Status = 'Conflict'
            Write-LogMessage -API 'Baselines' -tenant $TenantFilter -message "Conflict: `"$Label`" is configured with different settings at the same level by $(@($Item.ConflictWith) -join ' and ') - nothing runs until one of them changes. - Run $RunId" -Sev 'Warning'
            if ($PriorStatus -ne 'Conflict' -and $Item.AlertEnabled) { $Result.AlertEvent = 'Conflict' }
            Set-CIPPBaselineResult -Result $Result -Prior $Prior -RunId $RunId
            if ($Result.AlertEvent) { Send-CIPPBaselineAlert -Result $Result }
            return $Result
        }

        # A required variable left blank leaves the raw "%var%" token in the spec. That is not
        # a value: comparing it is permanent drift and writing it sends the literal string to
        # the API. Blank OPTIONAL fields are legitimate, and omitWhenBlank keys are pruned.
        $ConfiguredVariables = $Item.Variables ?? [PSCustomObject]@{}
        $Unresolved = @(($Definition.variables ?? [PSCustomObject]@{}).PSObject.Properties | Where-Object {
                $_.Value.required -eq $true -and
                [string]::IsNullOrEmpty("$($ConfiguredVariables.$($_.Name))")
            } | ForEach-Object { $_.Name })
        if ($Unresolved.Count -gt 0) {
            if ($GradeOnly) { return $null }
            $Missing = $Unresolved -join ', '
            Write-LogMessage -API 'Baselines' -tenant $TenantFilter -message "`"$Label`" is missing a value for $Missing - nothing is compared or changed until the baseline configures it. - Run $RunId" -Sev 'Error'
            $null = Add-CIPPBaselineHistoryEvent -TenantFilter $TenantFilter -Standard $Item.Standard -Mode $Mode -TriggeredBy $TriggeredBy -Outcome 'Error' -Detail "Not configured: no value for $Missing - the standard was skipped instead of comparing or writing the raw variable name." -RunId $RunId
            $Result.Outcome = 'Error'
            $Result.Status = $PriorStatus ?? 'No Data'
            return $Result
        }

        # Manual tasks: state lives on the resolved row; the operator completes them.
        if ($Definition.manual) {
            if ($GradeOnly) { return $null }
            $Manual = & $Render $Definition.manual $Item.Variables
            $Result.Manual = $Manual
            $Completed = [bool]($(try { $Prior.CurrentValue | ConvertFrom-Json } catch { $null })?.completed)
            $LastDone = if ("$($Prior.LastRemediated)" -match '^\d+$') { [int64]$Prior.LastRemediated } else { 0 }
            $ReopenSeconds = switch ($Manual.reopen) {
                'weekly' { 7 * 86400 }
                'monthly' { 30 * 86400 }
                'quarterly' { 91 * 86400 }
                default { 0 }
            }
            if ($Completed -and $ReopenSeconds -gt 0 -and $LastDone -gt 0 -and $Now -ge ($LastDone + $ReopenSeconds)) {
                $Completed = $false
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

        # read.array descends into each cached row's nested array and flattens the elements
        # into the candidate set BEFORE the filters run. filter.property may be a dot-path.
        $ReadCurrent = {
            $Data = @(New-CIPPDbRequest -TenantFilter $TenantFilter -Type $Definition.read.cacheType | Where-Object { $_ })
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

        # Cache pre-check for TEMPLATE standards only, keyed on read.requiredCaches which only
        # they declare: their verdicts drive policy deploys and their domains change under
        # external hands, so the cache must be complete, recent and live-consistent, collected
        # single-flight. Everything else tolerates normal CIPPDb cadence staleness.
        # The Where-Object is load-bearing: @($null).Count is 1, so an unfiltered @() test is
        # true for every definition that simply omits the property.
        $JustRefreshed = $false
        $CacheCollector = Get-Command -Name "Set-CIPPDBCache$($Definition.read.cacheType)" -ErrorAction SilentlyContinue
        $CollectorArgs = @{ TenantFilter = $TenantFilter }
        foreach ($Argument in ($Definition.read.collectorArgs ?? [PSCustomObject]@{}).PSObject.Properties) {
            $CollectorArgs[$Argument.Name] = $Argument.Value
        }
        if ($CacheCollector -and @($Definition.read.requiredCaches | Where-Object { $_ }).Count -gt 0) {
            $JustRefreshed = Wait-CIPPBaselineCacheReady -TenantFilter $TenantFilter -Definition $Definition -RunId $RunId
        }

        if ($Definition.prepare) {
            if ($Definition.prepare -notmatch '^Get-CIPPBaseline[A-Za-z0-9]+$' -or -not (Get-Command -Name $Definition.prepare -ErrorAction SilentlyContinue)) {
                throw "Prepare function $($Definition.prepare) is not available."
            }
            $Prepared = & $Definition.prepare -Item $Item -TenantFilter $TenantFilter
            if ($null -eq $Prepared.Current -and $CacheCollector -and -not $JustRefreshed) {
                try {
                    $null = & $CacheCollector @CollectorArgs
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
            # Poisoned-empty cache: the WHOLE policy family came back empty but this policy was
            # live within 7 days, so a flaky collection is likelier than a mass deletion.
            # Report No Data and retry rather than fanning out false drift and deploys.
            if ($Prepared.EmptyFamily) {
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
                    $null = & $CacheCollector @CollectorArgs
                    $Current = & $ReadCurrent
                } catch {
                    Write-Information "Baselines: cache collection for $($Definition.read.cacheType) on $TenantFilter failed: $($_.Exception.Message)"
                }
            }
        }
        $CheckBeforeRun = $Definition.checkBeforeRun -ne $false

        $ReadDefaults = $Definition.read.defaults
        $Differences = @()
        $PreFilterDifferences = @()
        $ProjectNode = $null
        $ProjectNode = {
            param($ExpectedNode, $CurrentNode)
            $Node = [PSCustomObject]@{}
            foreach ($Property in $ExpectedNode.PSObject.Properties) {
                $Value = if ($null -ne $CurrentNode) { $CurrentNode.$($Property.Name) } else { $null }
                # $anyOf sets are leaf declarations, not shapes to descend into.
                if ($Property.Value -is [System.Management.Automation.PSCustomObject] -and
                    -not $Property.Value.PSObject.Properties['$anyOf'] -and
                    $Value -is [System.Management.Automation.PSCustomObject]) {
                    $Value = & $ProjectNode $Property.Value $Value
                }
                $Node | Add-Member -NotePropertyName $Property.Name -NotePropertyValue $Value
            }
            $Node
        }
        if ($null -ne $Current) {
            $Projected = [PSCustomObject]@{}
            foreach ($Property in $Expected.PSObject.Properties.Name) {
                $Value = $Current.$Property
                $ExpectedLeaf = $Expected.$Property
                if (-not $Definition.prepare -and
                    $ExpectedLeaf -is [System.Management.Automation.PSCustomObject] -and
                    -not $ExpectedLeaf.PSObject.Properties['$anyOf'] -and
                    $Value -is [System.Management.Automation.PSCustomObject]) {
                    $Value = & $ProjectNode $ExpectedLeaf $Value
                }
                if ($null -eq $Value -and $null -ne $ReadDefaults -and $ReadDefaults.PSObject.Properties[$Property]) {
                    $Value = $ReadDefaults.$Property
                }
                $Projected | Add-Member -NotePropertyName $Property -NotePropertyValue $Value
            }
            $Result.CurrentValue = $Projected
            $CompareExpected = & $ResolveAnyOf $ExpectedTemplate $Current $true
            $CompareTypes = @($Prepared.CompareType | Where-Object { $_ })
            $Differences = @(Compare-CIPPIntuneObject -ReferenceObject $CompareExpected -DifferenceObject $Projected -CompareType $CompareTypes | Where-Object { $_ })

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
            # type-strict, regardless of compare type.
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

            # An accepted path tolerates that property's drift and only that property's.
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
        $PathAccepted = $PreFilterDifferences.Count -gt $Differences.Count

        # GradeOnly stops here: the verdict is the product, nothing is persisted, nothing
        # is remediated. An empty read grades non-compliant so the caller retries honestly.
        if ($GradeOnly) {
            return [PSCustomObject]@{
                Compliant    = [bool]$Compliant
                CurrentValue = $Result.CurrentValue
                Diff         = @($Differences)
            }
        }

        if ($Mode -ne 'compare' -and $Definition.delete -and $DenyDeleteKeys.Count -gt 0 -and $null -ne $Current) {
            $DeletedKeys = [System.Collections.Generic.List[string]]::new()
            foreach ($DenyKey in $DenyDeleteKeys) {
                $Target = $Current.$DenyKey
                # No target means the object is already gone - the verdict is stale.
                if (-not $Target -or -not "$($Target.id)") {
                    $DeletedKeys.Add($DenyKey)
                    continue
                }
                # The verdict author is the accountable party, captured before the verdict is
                # cleared and stamped on the audit event.
                $VerdictBy = "$($AcceptedPaths.$DenyKey.by)"
                try {
                    $DeleteExecutor = "Invoke-CIPPBaselineDelete$($Definition.delete.executor)"
                    if ($Definition.delete.executor -notmatch '^[A-Za-z0-9]+$' -or -not (Get-Command -Name $DeleteExecutor -ErrorAction SilentlyContinue)) {
                        throw "Unknown delete executor '$($Definition.delete.executor)' on $($Definition.name)."
                    }
                    & $DeleteExecutor -Target $Target -TenantFilter $TenantFilter
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

        $Expires = if ("$($Prior.DeviationExpires)" -match '^\d+$') { [int64]$Prior.DeviationExpires } else { 0 }
        $AcceptActive = $PriorStatus -eq 'Accepted' -and ($Expires -eq 0 -or $Now -lt $Expires)
        $RemediateOnExpire = $PriorStatus -eq 'Accepted' -and $Expires -gt 0 -and $Now -ge $Expires -and [bool]$Prior.RemediateOnExpire
        # A denied deviation is an operator order: remediate regardless of configured posture.
        $DeniedRemediate = $PriorStatus -eq 'Denied - Remediate Pending'

        if (-not $Compliant -and $null -ne $Current -and $AcceptActive) {
            $Result.Outcome = 'Drift'
            $Result.Status = 'Accepted'
            Set-CIPPBaselineResult -Result $Result -Prior $Prior -RunId $RunId
            return $Result
        }
        if (-not $Compliant -and $null -ne $Current -and $PriorStatus -eq 'Denied - Delete Pending') {
            # Either a ROW-level deny (which never bulk-deletes - deletion is a per-object
            # decision) or a per-path verdict whose delete failed. Both retry next run.
            $Result.Outcome = 'Drift'
            $Result.Status = 'Denied - Delete Pending'
            Set-CIPPBaselineResult -Result $Result -Prior $Prior -RunId $RunId
            return $Result
        }
        if ($Compliant -and $PathAccepted -and $PriorStatus -ne 'Denied - Remediate Pending') {
            # Aligned only because every deviating property is individually triaged.
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

        # Any live triage blocks remediation, including the fail-open path: remediation writes
        # the WHOLE expected object and would wipe an accepted property's deviation with it.
        $PathHold = $AcceptedKeys.Count -gt 0 -and ($PathAccepted -or $null -eq $Current)
        $TriageHold = $AcceptActive -or $PriorStatus -eq 'Denied - Delete Pending' -or $PathHold
        $RemediationAllowed = (($Mode -eq 'oneoff') -or ($Mode -eq 'run' -and ($Item.RemediateEnabled -or $RemediateOnExpire -or $DeniedRemediate))) -and -not $TriageHold
        $WriteNeeded = (-not $Compliant) -or $Force.IsPresent -or (-not $CheckBeforeRun)

        # Detect standards carry no remediate executor by design - report-only tripwires.
        if ($Mode -ne 'compare' -and $RemediationAllowed -and $WriteNeeded -and $Definition.remediate) {
            $ExpectedJson = ConvertTo-Json -Compress -Depth 100 -InputObject $Expected
            try {
                $Rendered = & $Render $Definition.remediate $Item.Variables
                # Resolved by convention, never a switch: a new executor is one new file.
                # Every executor takes the same three arguments; -Current is the read result
                # (declarative or prepared), which sweeps and object-scoped writes need and
                # everything else ignores.
                $ExecutorName = "Invoke-CIPPBaseline$($Definition.remediate.executor)"
                if ($Definition.remediate.executor -notmatch '^[A-Za-z0-9]+$' -or -not (Get-Command -Name $ExecutorName -ErrorAction SilentlyContinue)) {
                    throw "Unknown remediate executor '$($Definition.remediate.executor)' on $($Definition.name)."
                }
                & $ExecutorName -Remediate $Rendered -TenantFilter $TenantFilter -Current $Current
            } catch {
                Write-LogMessage -API 'Baselines' -tenant $TenantFilter -message "Failed to change `"$Label`" to $ExpectedJson`: $($_.Exception.Message) - Run $RunId" -Sev 'Error'
                $Result.Outcome = 'Error'
                Set-CIPPBaselineResult -Result $Result -Prior $Prior -RunId $RunId
                return $Result
            }
            Write-LogMessage -API 'Baselines' -tenant $TenantFilter -message "Successfully changed `"$Label`" to $ExpectedJson - Run $RunId" -Sev 'Info'
            # Optimistic post-write: the next run's cache read verifies it.
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
            # Nothing to honestly report and remediation does not apply, so nothing is written.
            Write-LogMessage -API 'Baselines' -tenant $TenantFilter -message "$($Item.Standard): no $($Definition.read.cacheType) data in CIPPDb after collection and remediation does not apply - skipped, nothing written." -Sev 'Info'
            $Result.Outcome = 'Skipped-NoCache'
            $Result.Status = $PriorStatus ?? 'No Data'
            return $Result
        } else {
            $Result.Outcome = 'Drift'
            # A pending deny is an operator order: a run that could not remediate must not
            # silently clear it. Alerts fire on the transition INTO drift, not every run.
            $Result.Status = if ("$PriorStatus".StartsWith('Denied')) { $PriorStatus } elseif ($PathAccepted) { 'Partially Accepted' } else { 'Drift' }
            if ($Result.Status -in @('Drift', 'Partially Accepted') -and $PriorStatus -notin @('Drift', 'Partially Accepted') -and $Item.AlertEnabled) { $Result.AlertEvent = 'Drift' }
        }

        Set-CIPPBaselineResult -Result $Result -Prior $Prior -RunId $RunId
        if ($Result.AlertEvent) { Send-CIPPBaselineAlert -Result $Result }
        return $Result
    } catch {
        Write-LogMessage -API 'Baselines' -tenant $TenantFilter -message "Baseline run failed for $($Item.Standard) on ${TenantFilter}: $($_.Exception.Message)" -Sev 'Error'
        # A failed verification must never overwrite the optimistic post-remediation row.
        if ($GradeOnly) { return $null }
        if ($Result) {
            $Result.Outcome = 'Error'
            try { Set-CIPPBaselineResult -Result $Result -Prior $Prior -RunId $RunId } catch { Write-Information "Set-CIPPBaselineResult failed: $($_.Exception.Message)" }
            return $Result
        }
    }
}
