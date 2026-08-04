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
        4. One Status per row: Compliant / Drift / Accepted / Denied - Remediate Pending /
           Denied - Delete Pending / Skipped - No License. Accepted holds until its unix
           expiry (optionally remediating on lapse); Denied - Remediate Pending forces
           remediation regardless of the configured posture. Writes only happen when needed:
           drift, -Force (manual runs), or "checkBeforeRun": false definitions.
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
        [switch]$Force
    )

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

        # 1a. Custom standards own their whole flow in their per-standard script.
        if ($Definition.custom -eq $true) {
            $CustomFunction = Get-Command -Name $Definition.customFunction -ErrorAction SilentlyContinue
            if (-not $CustomFunction) { throw "Custom function $($Definition.customFunction) is not available." }
            return (& $Definition.customFunction -Item $Item -Mode $Mode -TriggeredBy $TriggeredBy -Force:$Force)
        }

        # Prior resolved row: the deviation lifecycle and manual completion live on it.
        $ResolvedTable = Get-CippTable -tablename 'BaselineAlignment'
        $SafeTenant = ConvertTo-CIPPODataFilterValue -Value $TenantFilter
        $SafeStandard = ConvertTo-CIPPODataFilterValue -Value $Item.Standard
        $Prior = Get-CIPPAzDataTableEntity @ResolvedTable -Filter "PartitionKey eq '$SafeTenant' and StandardName eq '$SafeStandard'" | Select-Object -First 1
        $PriorStatus = $Prior.Status
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
            Set-CIPPBaselineResult -Result $Result -Prior $Prior
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
        # remediation applies, cache or not.
        $CheckBeforeRun = $Definition.checkBeforeRun -ne $false
        if ($null -eq $Current -and $CheckBeforeRun) {
            # Deliberately writes NOTHING: the row stays 'No Data' and retries next run.
            $Result.Outcome = 'Skipped-NoCache'
            $Result.Status = $PriorStatus ?? 'No Data'
            return $Result
        }

        # 3. Project to the expected keys (subset compare) and diff. A key the current object
        # lacks stays present as $null so the compare flags the presence mismatch.
        $Differences = @()
        if ($null -ne $Current) {
            $Projected = [PSCustomObject]@{}
            foreach ($Property in $Expected.PSObject.Properties.Name) {
                $Projected | Add-Member -NotePropertyName $Property -NotePropertyValue $Current.$Property
            }
            $Result.CurrentValue = $Projected
            # Compare-CIPPIntuneObject emits $null (not an empty set) when nothing differs.
            $Differences = @(Compare-CIPPIntuneObject -ReferenceObject $Expected -DifferenceObject $Projected | Where-Object { $_ })

            # Per-property acceptances (design addendum): an accepted path tolerates that
            # property's drift - and only that property's. Prefix matches cover nested paths.
            $AcceptedPaths = $(try { $Prior.AcceptedPaths | ConvertFrom-Json } catch { $null })
            $AcceptedKeys = @($AcceptedPaths.PSObject.Properties.Name)
            if ($AcceptedKeys.Count -gt 0) {
                $Differences = @($Differences | Where-Object {
                        $Property = $_.Property
                        -not ($AcceptedKeys | Where-Object { $Property -eq $_ -or $Property.StartsWith("$_.") })
                    })
            }
            $Result.Diff = $Differences
        }
        $Compliant = ($null -ne $Current) -and ($Differences.Count -eq 0)

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
            Set-CIPPBaselineResult -Result $Result -Prior $Prior
            return $Result
        }
        if (-not $Compliant -and $null -ne $Current -and $PriorStatus -eq 'Denied - Delete Pending') {
            # The delete executor lands with object-type standards; hold the status until then.
            $Result.Outcome = 'Drift'
            $Result.Status = 'Denied - Delete Pending'
            Set-CIPPBaselineResult -Result $Result -Prior $Prior
            return $Result
        }

        $RemediationAllowed = ($Mode -eq 'oneoff') -or ($Mode -eq 'run' -and ($Item.RemediateEnabled -or $RemediateOnExpire -or $DeniedRemediate))
        # Write only when needed: drift proves it, -Force (manual runs) demands it, and
        # checkBeforeRun=false standards cannot prove a write unnecessary.
        $WriteNeeded = (-not $Compliant) -or $Force.IsPresent -or (-not $CheckBeforeRun)

        if ($Mode -ne 'compare' -and $RemediationAllowed -and $WriteNeeded) {
            $Rendered = & $Render $Definition.remediate $Item.Variables
            switch ($Definition.remediate.executor) {
                'ExoRequest' { Invoke-CIPPBaselineExoRequest -Remediate $Rendered -TenantFilter $TenantFilter }
                'GraphRequest' { Invoke-CIPPBaselineGraphRequest -Remediate $Rendered -TenantFilter $TenantFilter }
                'CATemplate' { Invoke-CIPPBaselineCATemplate -Remediate $Rendered -TenantFilter $TenantFilter }
                default { throw "Unknown remediate executor '$($Definition.remediate.executor)' on $($Definition.name)." }
            }
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
            # checkBeforeRun=false with no cache AND no remediation applying: nothing ran,
            # so nothing is written - the row stays 'No Data' and retries next run.
            $Result.Outcome = 'Skipped-NoCache'
            $Result.Status = $PriorStatus ?? 'No Data'
            return $Result
        } else {
            $Result.Outcome = 'Drift'
            # A pending deny is an operator order - a run that could not remediate (compare
            # mode, or a failed attempt) must not silently clear it.
            $Result.Status = if ("$PriorStatus".StartsWith('Denied')) { $PriorStatus } else { 'Drift' }
            # Alerts fire on the transition INTO Drift, not every run.
            if ($Result.Status -eq 'Drift' -and $PriorStatus -ne 'Drift' -and $Item.AlertEnabled) { $Result.AlertEvent = 'Drift' }
        }

        Set-CIPPBaselineResult -Result $Result -Prior $Prior
        if ($Result.AlertEvent) { Send-CIPPBaselineAlert -Result $Result }
        return $Result
    } catch {
        Write-LogMessage -API 'Baselines' -tenant $TenantFilter -message "Baseline run failed for $($Item.Standard) on ${TenantFilter}: $($_.Exception.Message)" -Sev 'Error'
        if ($Result) {
            $Result.Outcome = 'Error'
            try { Set-CIPPBaselineResult -Result $Result -Prior $Prior } catch { Write-Information "Set-CIPPBaselineResult failed: $($_.Exception.Message)" }
            return $Result
        }
    }
}
