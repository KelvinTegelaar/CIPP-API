function Get-CIPPBaselineWorkItems {
    <#
    .SYNOPSIS
        Resolves every effective (tenant, standard instance) pair the engine must run.
    .DESCRIPTION
        Deltas are the source of truth; this walks the reconstructed baselines (rollout row +
        deltas) plus the ad-hoc tenant overrides and flattens them into one work item per
        (tenant, standard instance):
        - Stages are graduations: stages 1..currentStage all apply, and a later stage that
          reconfigures the same standard replaces the earlier stage's settings.
        - Scope precedence per the design doc: allTenants < group < tenant < ad-hoc override,
          whole-value replace.
        - Same rank, different baselines, SAME standard identity: identical settings dedupe
          (alert flags OR-merge); different variables or remediation posture is a CONFLICT -
          the pair is emitted with Conflicted=$true and the engine refuses to compare or
          remediate it until an operator changes one of the baselines. Identity is the
          instance key, except for definitions declaring instanceIdentity (e.g. the CA
          template id): there the SELECTED TEMPLATE is the identity, so the same template
          applied twice at one level collides while different templates coexist.
        - Excluded tenants get nothing from that baseline.
        Each item carries the configured variable values, action posture, inheritance tiers for
        the UI, and the baseline's alert destinations.
    .FUNCTIONALITY
        Internal
    #>
    [CmdletBinding()]
    param(
        $TenantFilter,
        $StandardName,
        $TemplateId
    )

    $Groups = @()
    try { $Groups = @(Get-TenantGroups) } catch { Write-Information "Get-CIPPBaselineWorkItems: tenant group lookup failed: $($_.Exception.Message)" }

    $Baselines = @(Get-CIPPBaseline)
    if ($TemplateId) { $Baselines = @($Baselines | Where-Object { $_.GUID -eq $TemplateId }) }
    $Definitions = @(Get-CIPPBaselineDefinition)

    # Canonical settings fingerprint: the variables only (property-order independent).
    # Conflict means the baselines disagree about the DESIRED STATE - the action posture
    # (remediate/alert flags) is deliberately excluded: identical settings with different
    # postures merge, strictest action wins, exactly like the alert flags OR-merge.
    $Fingerprint = {
        param($Variables)
        $Pairs = @(($Variables ?? [PSCustomObject]@{}).PSObject.Properties | Sort-Object -Property Name | ForEach-Object {
                '{0}={1}' -f $_.Name, (ConvertTo-Json -Compress -Depth 50 -InputObject $_.Value)
            })
        ($Pairs -join ';')
    }

    # key "<tenant>|<identity>" -> @{ Rank; Candidates = List of @{ Item; UpdatedAt; Fingerprint } }
    # Identity = the instance key, or Name#<identity-variable value> when the definition
    # declares instanceIdentity (the CA/Intune template id IS the instance's identity).
    $Effective = @{}
    $IdentityFor = {
        param($InstanceKey, $Variables)
        $BaseName = ($InstanceKey -split '#')[0]
        $Definition = $Definitions | Where-Object { $_.name -eq $BaseName } | Select-Object -First 1
        if ($Definition.instanceIdentity) {
            $IdentityValue = $Variables.$($Definition.instanceIdentity)
            if ($IdentityValue -is [System.Management.Automation.PSCustomObject]) { $IdentityValue = $IdentityValue.value }
            if ("$IdentityValue") { return ('{0}#{1}' -f $BaseName, $IdentityValue) }
        }
        $InstanceKey
    }

    foreach ($Baseline in $Baselines) {
        # How directly is each tenant covered: direct tenant assignment beats group beats allTenants.
        $AssignmentValues = @($Baseline.assignments.value)
        $HasAllTenants = $AssignmentValues -contains 'AllTenants'
        $AssignedGroups = @($Groups | Where-Object { $AssignmentValues -contains $_.Id -or $AssignmentValues -contains $_.Name })

        foreach ($State in $Baseline.tenantStates) {
            $Domain = $State.tenantFilter
            # TenantFilter accepts one domain or a list (an expanded tenant group).
            if ($TenantFilter -and $Domain -notin @($TenantFilter)) { continue }
            if ($Baseline.excludedTenants -contains $Domain) { continue }

            $Rank = if ($AssignmentValues -contains $Domain) { 2 }
            elseif (@($AssignedGroups | Where-Object { $_.Members.defaultDomainName -contains $Domain }).Count -gt 0) { 1 }
            elseif ($HasAllTenants) { 0 } else { 2 }
            $Scope = @('allTenants', 'group', 'tenant')[$Rank]

            # Ascending stage walk: later stages replace earlier configs for the same instance.
            $StageConfigs = @{}
            $StageNumbers = @{}
            $StageNames = @{}
            $StageNumber = 0
            foreach ($Stage in ($Baseline.stages | Select-Object -First $State.currentStage)) {
                $StageNumber++
                foreach ($Config in @($Stage.standardsConfig)) {
                    if (-not $Config) { continue }
                    $StageConfigs[$Config.instance] = $Config
                    $StageNumbers[$Config.instance] = $StageNumber
                    $StageNames[$Config.instance] = $Stage.name
                }
            }

            foreach ($InstanceKey in $StageConfigs.Keys) {
                if ($StandardName -and $InstanceKey -ne $StandardName) { continue }
                $Config = $StageConfigs[$InstanceKey]
                $Key = '{0}|{1}' -f $Domain, (& $IdentityFor $InstanceKey $Config.variables)
                $Candidate = @{
                    Rank      = $Rank
                    Stage     = $StageNumbers[$InstanceKey]
                    UpdatedAt = [int64]($Baseline.updatedAt ?? 0)
                    Item      = [PSCustomObject]@{
                        TenantFilter     = $Domain
                        TenantName       = $State.tenantName
                        Standard         = $InstanceKey
                        BaseName         = ($InstanceKey -split '#')[0]
                        TemplateId       = $Baseline.GUID
                        TemplateName     = $Baseline.templateName
                        Variables        = ($Config.variables ?? [PSCustomObject]@{})
                        RemediateEnabled = [bool]$Config.remediateEnabled
                        AlertEnabled     = [bool]$Config.alertEnabled
                        AlertOnRemediate = [bool]$Config.alertOnRemediate
                        SourceScope      = $Scope
                        SourceTemplate   = $Baseline.templateName
                        Stage            = $StageNumbers[$InstanceKey]
                        StageName        = $StageNames[$InstanceKey]
                        AlertEmails      = $Baseline.alertEmails
                        AlertWebhookUrl  = $Baseline.alertWebhookUrl
                        Tiers            = @([PSCustomObject]@{
                                templateName     = $Baseline.templateName
                                assignedTo       = ($Baseline.assignedTenants -join ', ')
                                variables        = ($Config.variables ?? [PSCustomObject]@{})
                                remediateEnabled = [bool]$Config.remediateEnabled
                                alertEnabled     = [bool]$Config.alertEnabled
                                alertOnRemediate = [bool]$Config.alertOnRemediate
                                effective        = $true
                            })
                    }
                }
                $Candidate.Fingerprint = & $Fingerprint $Config.variables

                $Existing = $Effective[$Key]
                if (-not $Existing -or $Candidate.Rank -gt $Existing.Rank) {
                    # A more specific scope whole-value replaces everything below it -
                    # including any conflict that existed at the lower rank.
                    $Candidates = [System.Collections.Generic.List[object]]::new()
                    $Candidates.Add($Candidate)
                    $Effective[$Key] = @{ Rank = $Candidate.Rank; Candidates = $Candidates }
                } elseif ($Candidate.Rank -eq $Existing.Rank) {
                    $Twin = $Existing.Candidates | Where-Object { $_.Fingerprint -eq $Candidate.Fingerprint } | Select-Object -First 1
                    if ($Twin) {
                        # Identical settings from another baseline: dedupe. The strictest
                        # request from EITHER baseline survives the merge - a wish to
                        # remediate or alert always wins over report-only/muted. Both
                        # sources stay visible in the inheritance tiers with their own
                        # posture, so the merge is explainable in the UI.
                        $Twin.Item.RemediateEnabled = [bool]($Twin.Item.RemediateEnabled -or $Candidate.Item.RemediateEnabled)
                        $Twin.Item.AlertEnabled = [bool]($Twin.Item.AlertEnabled -or $Candidate.Item.AlertEnabled)
                        $Twin.Item.AlertOnRemediate = [bool]($Twin.Item.AlertOnRemediate -or $Candidate.Item.AlertOnRemediate)
                        $Twin.Item.SourceTemplate = @(@($Twin.Item.SourceTemplate -split ', ') + $Candidate.Item.TemplateName | Where-Object { $_ } | Select-Object -Unique) -join ', '
                        $Twin.Item.Tiers = @(@($Twin.Item.Tiers) + @($Candidate.Item.Tiers) | Where-Object { $_ })
                        if ($Candidate.UpdatedAt -gt $Twin.UpdatedAt) { $Twin.UpdatedAt = $Candidate.UpdatedAt }
                    } else {
                        # Same level, same identity, different settings: conflict.
                        $Existing.Candidates.Add($Candidate)
                    }
                }
                # Lower rank than the current winner: ignored entirely.
            }
        }
    }

    # Ad-hoc tenant overrides (templateId '') replace whatever a baseline resolved, or stand alone.
    $DeltaTable = Get-CippTable -tablename 'Baselines'
    $OverrideFilter = "PartitionKey eq 'standardItem' and templateId eq '' and scope eq 'tenant'"
    foreach ($Delta in @(Get-CIPPAzDataTableEntity @DeltaTable -Filter $OverrideFilter)) {
        if (-not $Delta) { continue }
        if ($TenantFilter -and $Delta.scopeId -notin @($TenantFilter)) { continue }
        if ($StandardName -and $Delta.standardName -ne $StandardName) { continue }
        if ($TemplateId) { continue } # a baseline-scoped run never picks up ad-hoc overrides of other config
        $Variables = $(try { $Delta.expectedValue | ConvertFrom-Json -ErrorAction Stop } catch { [PSCustomObject]@{} }) ?? [PSCustomObject]@{}
        # An override targets a specific resolved instance: find the effective entry whose
        # winning item carries that instance key (identity-keyed entries included), and
        # only fall back to computing an identity when the override stands alone.
        $Key = $null
        foreach ($ExistingKey in @($Effective.Keys)) {
            if ($ExistingKey -notlike "$($Delta.scopeId)|*") { continue }
            $KeyWinner = @($Effective[$ExistingKey].Candidates | Sort-Object -Property UpdatedAt -Descending)[0]
            if ($KeyWinner.Item.Standard -eq $Delta.standardName) { $Key = $ExistingKey; break }
        }
        if (-not $Key) { $Key = '{0}|{1}' -f $Delta.scopeId, (& $IdentityFor $Delta.standardName $Variables) }
        $Winning = if ($Effective[$Key]) { @($Effective[$Key].Candidates | Sort-Object -Property UpdatedAt -Descending)[0] } else { $null }
        $Tiers = [System.Collections.Generic.List[object]]::new()
        foreach ($Tier in @($Winning.Item.Tiers)) {
            if (-not $Tier) { continue }
            $Tier.effective = $false
            $Tiers.Add($Tier)
        }
        $Tiers.Add([PSCustomObject]@{
                templateName     = 'Tenant Override'
                assignedTo       = $Delta.scopeId
                variables        = $Variables
                remediateEnabled = [bool]$Delta.remediateEnabled
                alertEnabled     = [bool]$Delta.alertEnabled
                alertOnRemediate = [bool]$Delta.alertOnRemediate
                effective        = $true
            })
        $OverrideCandidates = [System.Collections.Generic.List[object]]::new()
        $OverrideCandidates.Add(@{
                Rank        = 3
                Stage       = $Winning.Stage ?? 1
                UpdatedAt   = [int64]($Delta.updatedAt ?? 0)
                Fingerprint = & $Fingerprint $Variables
                Item        = [PSCustomObject]@{
                    TenantFilter     = $Delta.scopeId
                    TenantName       = $Winning.Item.TenantName ?? $Delta.scopeId
                    Standard         = $Delta.standardName
                    BaseName         = ($Delta.standardName -split '#')[0]
                    TemplateId       = ''
                    TemplateName     = 'Tenant Override'
                    Variables        = $Variables
                    RemediateEnabled = [bool]$Delta.remediateEnabled
                    AlertEnabled     = [bool]$Delta.alertEnabled
                    AlertOnRemediate = [bool]$Delta.alertOnRemediate
                    SourceScope      = 'tenant'
                    SourceTemplate   = 'Tenant Override'
                    Stage            = $Winning.Stage ?? 1
                    StageName        = $Winning.Item.StageName ?? ''
                    AlertEmails      = $Winning.Item.AlertEmails ?? ''
                    AlertWebhookUrl  = $Winning.Item.AlertWebhookUrl ?? ''
                    Tiers            = @($Tiers)
                }
            })
        $Effective[$Key] = @{ Rank = 3; Candidates = $OverrideCandidates }
    }

    foreach ($Entry in $Effective.Values) {
        $Candidates = @($Entry.Candidates | Sort-Object -Property UpdatedAt -Descending)
        if ($Candidates.Count -le 1) {
            $Candidates[0].Item
            continue
        }
        # Same rank, same identity, different settings: even the expected value is
        # ambiguous. Emit one item flagged Conflicted per involved INSTANCE KEY (multi-
        # instance standards configure the same identity under different keys - every
        # configured instance must show Conflict, not one Conflict plus a stale row).
        # The engine parks each row at 'Conflict' and refuses to compare or remediate;
        # every colliding source shows in the inheritance tiers (none effective).
        $ConflictTiers = [System.Collections.Generic.List[object]]::new()
        $ConflictAlert = $false
        foreach ($ConflictCandidate in $Candidates) {
            $ConflictAlert = $ConflictAlert -or [bool]$ConflictCandidate.Item.AlertEnabled
            foreach ($Tier in @($ConflictCandidate.Item.Tiers)) {
                if (-not $Tier) { continue }
                $Tier.effective = $false
                $ConflictTiers.Add($Tier)
            }
        }
        $ConflictNames = @($Candidates | ForEach-Object { $_.Item.TemplateName } | Select-Object -Unique)
        $EmittedKeys = [System.Collections.Generic.HashSet[string]]::new()
        foreach ($ConflictCandidate in $Candidates) {
            if (-not $EmittedKeys.Add("$($ConflictCandidate.Item.Standard)")) { continue }
            $ConflictItem = $ConflictCandidate.Item.PSObject.Copy()
            $ConflictItem.RemediateEnabled = $false
            $ConflictItem.AlertEnabled = $ConflictAlert
            $ConflictItem.Tiers = @($ConflictTiers)
            # Attribute the row to every colliding baseline, not just its own source.
            $ConflictItem.SourceTemplate = ($ConflictNames -join ', ')
            $ConflictItem | Add-Member -NotePropertyName Conflicted -NotePropertyValue $true -Force
            $ConflictItem | Add-Member -NotePropertyName ConflictWith -NotePropertyValue $ConflictNames -Force
            $ConflictItem
        }
    }
}
