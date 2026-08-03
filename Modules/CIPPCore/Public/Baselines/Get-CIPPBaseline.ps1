function Get-CIPPBaseline {
    <#
    .SYNOPSIS
        Returns baselines reconstructed from their source-of-truth rows.
    .DESCRIPTION
        There is no baseline blob. A baseline is reassembled on read (design doc §4.1/§13.3):
        the BaselineRollouts row carries the baseline-level data (name, description,
        exclusions, alert destinations, ordered stage definitions), and the Baseline delta
        rows carry every standard's configuration, scope, stage membership, and action posture.
        Assignment derives from the delta scopes. Per-stage occupancy and per-tenant stage
        progress come from BaselineRolloutState; an assigned tenant without a state row sits
        in stage 1 since the baseline was assigned.
    .FUNCTIONALITY
        Internal
    #>
    [CmdletBinding()]
    param($ID)

    $RolloutTable = Get-CippTable -tablename 'BaselineRollouts'
    $Filter = "PartitionKey eq 'rollout'"
    if ($ID) {
        $SafeID = ConvertTo-CIPPODataFilterValue -Value $ID
        $Filter = "PartitionKey eq 'rollout' and RowKey eq '$SafeID'"
    }
    $RolloutRows = Get-CIPPAzDataTableEntity @RolloutTable -Filter $Filter
    if (-not $RolloutRows) { return }

    $DeltaTable = Get-CippTable -tablename 'Baselines'
    $StateTable = Get-CippTable -tablename 'BaselineRolloutState'

    # Tenant + group context for assignment expansion and display names.
    $AllTenants = @()
    try { $AllTenants = @(Get-Tenants) } catch { Write-Information "Get-CIPPBaseline: tenant list lookup failed: $($_.Exception.Message)" }
    $Groups = @()
    try { $Groups = @(Get-TenantGroups) } catch { Write-Information "Get-CIPPBaseline: tenant group lookup failed: $($_.Exception.Message)" }
    $TenantNames = @{}
    foreach ($Tenant in $AllTenants) {
        if ($Tenant.defaultDomainName) { $TenantNames[$Tenant.defaultDomainName] = $Tenant.displayName }
    }

    foreach ($RolloutRow in $RolloutRows) {
        # One corrupted baseline must never take down the whole list: log and show the rest.
        try {
            $GUID = $RolloutRow.RowKey
            $StageDefinitions = @($RolloutRow.Stages | ConvertFrom-Json -ErrorAction Stop)
            $ExcludedTenants = @()
            try { if ($RolloutRow.excludedTenants) { $ExcludedTenants = @($RolloutRow.excludedTenants | ConvertFrom-Json) } } catch { }

            # The standards per stage come from the delta rows for this baseline.
            $SafeGuid = ConvertTo-CIPPODataFilterValue -Value $GUID
            $Deltas = @(Get-CIPPAzDataTableEntity @DeltaTable -Filter "PartitionKey eq 'standardItem' and templateId eq '$SafeGuid'")

            $StageNumber = 0
            $Stages = foreach ($StageDefinition in $StageDefinitions) {
                $StageNumber++
                $CurrentNumber = $StageNumber
                # One delta exists per scope; a stage's standards are the unique instance keys.
                $StageDeltas = @($Deltas | Where-Object { [int]$_.stage -eq $CurrentNumber } | Sort-Object -Property standardName -Unique)
                [PSCustomObject]@{
                    name            = $StageDefinition.name
                    logic           = $StageDefinition.logic
                    conditions      = @($StageDefinition.conditions)
                    standards       = @($StageDeltas.standardName)
                    standardsConfig = @($StageDeltas | ForEach-Object {
                            [PSCustomObject]@{
                                standard         = (($_.standardName) -split '#')[0]
                                instance         = $_.standardName
                                variables        = $(try { $_.expectedValue | ConvertFrom-Json } catch { [PSCustomObject]@{} })
                                remediateEnabled = [bool]$_.remediateEnabled
                                alertEnabled     = [bool]$_.alertEnabled
                                alertOnRemediate = [bool]$_.alertOnRemediate
                            }
                        })
                }
            }
            $Stages = @($Stages)

            # Assignment derives from the delta scopes: unique (scope, scopeId) pairs.
            # scopeId is the stable key (group ID / tenant domain); scopeName is for display.
            $AssignmentScopes = @($Deltas | ForEach-Object {
                    [PSCustomObject]@{ scope = $_.scope; scopeId = $_.scopeId; scopeName = ($_.scopeName ?? $_.scopeId) }
                } | Sort-Object -Property scope, scopeId -Unique)
            $AssignedTenants = @($AssignmentScopes | ForEach-Object {
                    if ($_.scope -eq 'allTenants') { 'AllTenants' } else { $_.scopeName }
                } | Where-Object { $_ } | Select-Object -Unique)

            $UniqueStandards = @($Deltas.standardName | ForEach-Object { ($_ -split '#')[0] } | Select-Object -Unique)

            # Posture summary: multiple stages = Staged; otherwise Remediate/Report from the deltas.
            $RemediationPosture = if ($Stages.Count -gt 1) {
                'Staged'
            } elseif (@($Deltas | Where-Object { -not [bool]$_.remediateEnabled }).Count -gt 0) {
                'Report'
            } else {
                'Remediate'
            }

            # Builds one tenant state entry (explicit rollout state or the stage-1 default).
            $NewState = {
                param($TenantDomain, $CurrentStage, $EnteredStageAt)
                # CIPP stores time as unix seconds. Normalize whatever the column holds
                # (Azure hands datetime columns back as DateTimeOffset) to unix.
                $EnteredStageAt = if ($EnteredStageAt -is [System.DateTimeOffset]) {
                    $EnteredStageAt.ToUnixTimeSeconds()
                } elseif ($EnteredStageAt -is [datetime]) {
                    ([System.DateTimeOffset]$EnteredStageAt.ToUniversalTime()).ToUnixTimeSeconds()
                } elseif ("$EnteredStageAt") {
                    [int64]$EnteredStageAt
                } else { $null }
                $NextStageDef = if ($CurrentStage -lt $Stages.Count) { $Stages[$CurrentStage] } else { $null }
                $TimeCondition = $NextStageDef.conditions | Where-Object { $_.type -eq 'time' } | Select-Object -First 1
                $EstimatedAdvanceAt = if ($TimeCondition -and $EnteredStageAt) {
                    $Multiplier = if ($TimeCondition.unit -eq 'weeks') { 7 } else { 1 }
                    $EnteredStageAt + ([int64]$TimeCondition.days * $Multiplier * 86400)
                } else { $null }
                [PSCustomObject]@{
                    tenantFilter       = $TenantDomain
                    tenantName         = $TenantNames[$TenantDomain] ?? $TenantDomain
                    currentStage       = $CurrentStage
                    totalStages        = $Stages.Count
                    stageName          = $Stages[$CurrentStage - 1].name
                    enteredStageAt     = $EnteredStageAt
                    nextStage          = $NextStageDef
                    nextStageName      = $NextStageDef.name
                    estimatedAdvanceAt = $EstimatedAdvanceAt
                    manualAdvance      = [bool]($NextStageDef.conditions | Where-Object { $_.type -eq 'manual' })
                }
            }

            # Explicit rollout state rows for this baseline.
            $StateRows = Get-CIPPAzDataTableEntity @StateTable -Filter "PartitionKey eq '$SafeGuid'"
            $TenantStates = [System.Collections.Generic.List[object]]::new()
            foreach ($State in $StateRows) {
                $TenantStates.Add((& $NewState $State.RowKey ([int]($State.currentStage ?? 1)) $State.enteredStageAt))
            }

            # Every assigned tenant without a state row defaults to stage 1 since assignment.
            # Groups expand by ID so renames never detach members.
            $AssignedDomains = foreach ($Assignment in $AssignmentScopes) {
                if ($Assignment.scope -eq 'allTenants') {
                    $AllTenants.defaultDomainName
                } elseif ($Assignment.scope -eq 'group') {
                    ($Groups | Where-Object { $_.Id -eq $Assignment.scopeId } | Select-Object -First 1).Members.defaultDomainName
                } else {
                    $Assignment.scopeId
                }
            }
            $AssignedDomains = @($AssignedDomains | Where-Object { $_ -and $ExcludedTenants -notcontains $_ } | Select-Object -Unique)
            foreach ($Domain in $AssignedDomains) {
                if ($TenantStates.tenantFilter -notcontains $Domain) {
                    $TenantStates.Add((& $NewState $Domain 1 $RolloutRow.updatedAt))
                }
            }

            # Occupancy: tenants per stage plus the earliest upcoming time-based advance.
            $StageNumber = 0
            $Occupancy = foreach ($Stage in $Stages) {
                $StageNumber++
                $CurrentNumber = $StageNumber
                $InStage = @($TenantStates | Where-Object { $_.currentStage -eq $CurrentNumber })
                $NextAdvanceAt = ($InStage.estimatedAdvanceAt | Where-Object { $_ } | Sort-Object | Select-Object -First 1)
                [PSCustomObject]@{
                    stage          = $CurrentNumber
                    name           = $Stage.name
                    standardsCount = @($Stage.standards).Count
                    tenants        = @($InStage.tenantName)
                    nextAdvanceAt  = $NextAdvanceAt
                }
            }

            [PSCustomObject]@{
                GUID               = $GUID
                templateName       = $RolloutRow.templateName
                baselineName       = $RolloutRow.templateName
                description        = $RolloutRow.description
                assignedTenants    = $AssignedTenants
                excludedTenants    = $ExcludedTenants
                alertEmails        = $RolloutRow.alertEmails
                alertWebhookUrl    = $RolloutRow.alertWebhookUrl
                standardsCount     = $UniqueStandards.Count
                stageNames         = @($Stages.name)
                stages             = $Stages
                remediationPosture = $RemediationPosture
                updatedAt          = $(if ($RolloutRow.updatedAt -is [System.DateTimeOffset]) { $RolloutRow.updatedAt.ToUnixTimeSeconds() } else { $RolloutRow.updatedAt })
                updatedBy          = $RolloutRow.updatedBy
                occupancy          = @($Occupancy)
                tenantStates       = @($TenantStates | Sort-Object -Property @{Expression = 'currentStage'; Descending = $true }, tenantName)
            }
        } catch {
            Write-LogMessage -API 'Baselines' -message "Skipped baseline $($RolloutRow.RowKey) ($($RolloutRow.templateName)) - failed to reconstruct it: $($_.Exception.Message)" -Sev 'Warning'
        }
    }
}
