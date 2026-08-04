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
          whole-value replace. Two baselines hitting the same pair at the same rank resolve to
          the most recently updated baseline.
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

    # key "<tenant>|<instance>" -> @{ Item; Rank; Stage; UpdatedAt }
    $Effective = @{}

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
                $Key = '{0}|{1}' -f $Domain, $InstanceKey
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
                                templateName = $Baseline.templateName
                                assignedTo   = ($Baseline.assignedTenants -join ', ')
                                variables    = ($Config.variables ?? [PSCustomObject]@{})
                                effective    = $true
                            })
                    }
                }
                $Existing = $Effective[$Key]
                if (-not $Existing -or
                    $Candidate.Rank -gt $Existing.Rank -or
                    ($Candidate.Rank -eq $Existing.Rank -and $Candidate.UpdatedAt -gt $Existing.UpdatedAt)) {
                    $Effective[$Key] = $Candidate
                }
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
        $Key = '{0}|{1}' -f $Delta.scopeId, $Delta.standardName
        $Tiers = [System.Collections.Generic.List[object]]::new()
        foreach ($Tier in @($Effective[$Key].Item.Tiers)) {
            if (-not $Tier) { continue }
            $Tier.effective = $false
            $Tiers.Add($Tier)
        }
        $Tiers.Add([PSCustomObject]@{
                templateName = 'Tenant Override'
                assignedTo   = $Delta.scopeId
                variables    = $Variables
                effective    = $true
            })
        $Effective[$Key] = @{
            Rank      = 3
            Stage     = $Effective[$Key].Stage ?? 1
            UpdatedAt = [int64]($Delta.updatedAt ?? 0)
            Item      = [PSCustomObject]@{
                TenantFilter     = $Delta.scopeId
                TenantName       = $Effective[$Key].Item.TenantName ?? $Delta.scopeId
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
                Stage            = $Effective[$Key].Stage ?? 1
                StageName        = $Effective[$Key].Item.StageName ?? ''
                AlertEmails      = $Effective[$Key].Item.AlertEmails ?? ''
                AlertWebhookUrl  = $Effective[$Key].Item.AlertWebhookUrl ?? ''
                Tiers            = @($Tiers)
            }
        }
    }

    foreach ($Entry in $Effective.Values) { $Entry.Item }
}
