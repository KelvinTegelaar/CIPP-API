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
        2. Read the current value from the CIPPDb cache (cacheType -> filter[] -> object
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
        $Prior = Get-CIPPAzDataTableEntity @ResolvedTable -Filter "PartitionKey eq '$SafeTenant' and StandardName eq '$SafeStandard'" | Select-Object -First 1
        $PriorStatus = $Prior.Status
        # Per-property acceptances (design addendum): parsed up front because they shape the
        # compare, the remediation gate, and the resulting status.
        $AcceptedPaths = $(try { $Prior.AcceptedPaths | ConvertFrom-Json } catch { $null })
        $AcceptedKeys = @($AcceptedPaths.PSObject.Properties.Name | Where-Object { $_ })
        $Expected = & $Render $Definition.expected $Item.Variables
        $Tiers = foreach ($Tier in @($Item.Tiers)) {
            if (-not $Tier) { continue }
            [PSCustomObject]@{
                templateName = $Tier.templateName
                assignedTo   = $Tier.assignedTo
                value        = (& $Render $Definition.expected $Tier.variables)
                effective    = [bool]$Tier.effective
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
            Inheritance         = @($Tiers)
            AlertEvent          = $null
            CacheType           = $Definition.read.cacheType
        }

        # 1b. Manual tasks: state lives on the resolved row; the operator completes them.
        if ($Definition.manual) {
            $Manual = & $Render $Definition.manual $Item.Variables
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
            foreach ($Condition in @($Definition.read.filter)) {
                if (-not $Condition) { continue }
                $Match = & $Render $Condition.value $Item.Variables
                $Property = $Condition.property
                $Data = @($Data | Where-Object {
                        switch ($Condition.operator) {
                            'ne' { $_.$Property -ne $Match }
                            'startsWith' { "$($_.$Property)".StartsWith("$Match") }
                            'notStartsWith' { -not "$($_.$Property)".StartsWith("$Match") }
                            default { $_.$Property -eq $Match }
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
        $Current = & $ReadCurrent
        if ($null -eq $Current) {
            $Collector = Get-Command -Name "Set-CIPPDBCache$($Definition.read.cacheType)" -ErrorAction SilentlyContinue
            if ($Collector) {
                try {
                    $null = & $Collector -TenantFilter $TenantFilter
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
            # Compare-CIPPIntuneObject emits $null (not an empty set) when nothing differs.
            $Differences = @(Compare-CIPPIntuneObject -ReferenceObject $Expected -DifferenceObject $Projected | Where-Object { $_ })

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
        }
        $Compliant = ($null -ne $Current) -and ($Differences.Count -eq 0)
        # True when accepted paths actually swallowed drift this run - the row's alignment
        # (full or partial) is owed to acceptances, not to the tenant matching the baseline.
        $PathAccepted = $PreFilterDifferences.Count -gt $Differences.Count

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
            # The delete executor lands with object-type standards; hold the status until then.
            $Result.Outcome = 'Drift'
            $Result.Status = 'Denied - Delete Pending'
            Set-CIPPBaselineResult -Result $Result -Prior $Prior -RunId $RunId
            return $Result
        }
        if ($Compliant -and $PathAccepted -and -not "$PriorStatus".StartsWith('Denied')) {
            # Aligned only because every deviating property is individually accepted: that
            # scores as Accepted (aligned via acceptance), not Compliant, and the tolerated
            # diff stays visible in history.
            $Result.Diff = $PreFilterDifferences
            $Result.Outcome = 'Drift'
            $Result.Status = 'Accepted'
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

        if ($Mode -ne 'compare' -and $RemediationAllowed -and $WriteNeeded) {
            $ExpectedJson = ConvertTo-Json -Compress -Depth 100 -InputObject $Expected
            try {
                $Rendered = & $Render $Definition.remediate $Item.Variables
                switch ($Definition.remediate.executor) {
                    'ExoRequest' { Invoke-CIPPBaselineExoRequest -Remediate $Rendered -TenantFilter $TenantFilter }
                    'GraphRequest' { Invoke-CIPPBaselineGraphRequest -Remediate $Rendered -TenantFilter $TenantFilter }
                    'TeamsRequest' { Invoke-CIPPBaselineTeamsRequest -Remediate $Rendered -TenantFilter $TenantFilter }
                    'SPOTenant' { Invoke-CIPPBaselineSPOTenant -Remediate $Rendered -TenantFilter $TenantFilter }
                    'CATemplate' { Invoke-CIPPBaselineCATemplate -Remediate $Rendered -TenantFilter $TenantFilter }
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
