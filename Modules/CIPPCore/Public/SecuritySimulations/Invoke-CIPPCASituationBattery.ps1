function Invoke-CIPPCASituationBattery {
    <#
    .SYNOPSIS
        Evaluates every predefined sign-in situation against a tenant's live Conditional Access.
    .DESCRIPTION
        Each situation names a persona and sign-in conditions. The admin, user and guest accounts are
        picked from the cache unless -IdentityOverrides names them (persona -> user id), and situations
        marked countryFromSelection sign in from -Country (default RU).
    .FUNCTIONALITY
        Internal
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]$TenantFilter,
        [hashtable]$IdentityOverrides,
        [string]$Country
    )

    $Country = if ([string]::IsNullOrWhiteSpace($Country)) { 'RU' } else { "$Country".Trim().ToUpperInvariant() }
    $Capabilities = $(try { Get-CIPPTenantCapabilities -TenantFilter $TenantFilter } catch { $null })
    $HasP2 = $Capabilities.AAD_PREMIUM_P2 -eq $true
    $RiskConditions = @('signInRiskLevel', 'userRiskLevel', 'insiderRiskLevel')
    $Excluded = [System.Collections.Generic.List[object]]::new()
    $Situations = @(foreach ($Situation in @(Get-CIPPSecuritySimulationSituation)) {
            $NeedsP2 = @(($Situation.conditions ?? [PSCustomObject]@{}).PSObject.Properties.Name | Where-Object { $RiskConditions -contains $_ }).Count -gt 0
            if ($NeedsP2 -and -not $HasP2) {
                $Excluded.Add([PSCustomObject]@{ id = "$($Situation.id)"; title = "$($Situation.title)"; reason = 'Requires Entra ID P2' })
                continue
            }
            $Situation
        })
    $Users = @(Get-CIPPSimulationCache -TenantFilter $TenantFilter -Type 'Users')
    $Roles = @(Get-CIPPSimulationCache -TenantFilter $TenantFilter -Type 'Roles')
    $Policies = @(Get-CIPPSimulationCache -TenantFilter $TenantFilter -Type 'ConditionalAccessPolicies')

    $UsersById = @{}
    foreach ($User in $Users) { if ($User.id) { $UsersById["$($User.id)"] = $User } }

    $PrivilegedTemplates = @(Get-CIPPPrivilegedRoleTemplateIds)
    $AdminIds = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    foreach ($Role in @($Roles | Where-Object { $PrivilegedTemplates -contains $_.roleTemplateId })) {
        foreach ($Member in @($Role.members | Where-Object { $_.id })) { $null = $AdminIds.Add("$($Member.id)") }
    }
    $AdminCandidates = @($Users | Where-Object { $_.id -and $AdminIds.Contains("$($_.id)") -and $_.accountEnabled -eq $true -and "$($_.userType)" -ne 'Guest' } |
            Sort-Object -Property displayName | ForEach-Object {
                [PSCustomObject]@{ userId = "$($_.id)"; displayName = "$($_.displayName)"; userPrincipalName = "$($_.userPrincipalName)" }
            })

    $Identities = @{}
    foreach ($Persona in @('admin', 'user', 'guest')) {
        $OverrideId = $(if ($IdentityOverrides) { "$($IdentityOverrides[$Persona])" } else { '' })
        $Selected = $(if ($OverrideId) { $UsersById[$OverrideId] } else { $null })
        if ($Selected) {
            $Identities[$Persona] = [PSCustomObject]@{
                persona           = $Persona
                kind              = 'Selected'
                userId            = "$($Selected.id)"
                displayName       = "$($Selected.displayName)"
                userPrincipalName = "$($Selected.userPrincipalName)"
            }
        } else {
            $Identities[$Persona] = Resolve-CIPPSimulationIdentity -TenantFilter $TenantFilter -Persona $Persona -Users $Users -Roles $Roles -Policies $Policies
        }
    }

    $ConditionsFor = {
        param($Situation)
        if ($Situation.countryFromSelection -ne $true) { return $Situation.conditions }
        $Conditions = $Situation.conditions | Select-Object -Property * -ExcludeProperty ipAddress
        $Conditions | Add-Member -NotePropertyName country -NotePropertyValue $Country -Force
        $Conditions
    }

    $Bodies = [System.Collections.Generic.List[object]]::new()
    foreach ($Situation in $Situations) {
        $Persona = $(if ("$($Situation.persona)") { "$($Situation.persona)" } else { 'user' })
        $Identity = $Identities[$Persona]
        if (-not $Identity) { continue }
        $Bodies.Add((New-CIPPCAWhatIfRequest -UserId $Identity.userId -IncludeApplications $Situation.includeApplications -Conditions (& $ConditionsFor $Situation)))
    }

    $Evaluations = if ($Bodies.Count -gt 0) { @(Invoke-CIPPCAWhatIf -TenantFilter $TenantFilter -Bodies @($Bodies)) } else { @() }

    $Rows = [System.Collections.Generic.List[object]]::new()
    $EvaluableIndex = 0
    foreach ($Situation in $Situations) {
        $Persona = $(if ("$($Situation.persona)") { "$($Situation.persona)" } else { 'user' })
        $Identity = $Identities[$Persona]
        $Expected = $(if ("$($Situation.expected)") { "$($Situation.expected)" } else { 'blocked' })
        $Row = [PSCustomObject]@{
            id                  = "$($Situation.id)"
            group               = "$($Situation.group)"
            title               = "$($Situation.title)"
            persona             = $Persona
            identity            = $(if ($Identity) { $Identity.userPrincipalName } else { $null })
            expected            = $Expected
            outcome             = 'Not evaluated'
            pass                = $null
            requiredControls    = @()
            blockedBy           = @()
            reportOnlyWouldStop = @()
            missingControl      = $(if ($Situation.missingControl) { "$($Situation.missingControl.text)" } else { '' })
            fix                 = $Situation.missingControl.fix
            conditions          = (& $ConditionsFor $Situation)
            policies            = @()
            error               = $null
        }
        if (-not $Identity) {
            $Row.error = "No $Persona account is available in the cache."
            $Rows.Add($Row)
            continue
        }
        $Evaluation = $Evaluations[$EvaluableIndex]
        $EvaluableIndex++
        if ($Evaluation.Error) {
            $Row.error = "$($Evaluation.Error)"
            $Rows.Add($Row)
            continue
        }
        $CanSatisfy = if ($Expected -in @('mfa', 'phishingResistant')) { @() } else { @($Situation.attackerCanSatisfy | Where-Object { $_ }) }
        $Verdict = Get-CIPPCAWhatIfVerdict -Policies $Evaluation.Policies -AttackerCanSatisfy $CanSatisfy -Expected $Expected
        $Row.outcome = if ($Verdict.detail -eq 'blockedByPolicy') { 'Blocked' }
        elseif ($Verdict.detail -eq 'challenged') { 'Requires {0}' -f ($Verdict.requiredControls -join ', ') }
        elseif ($Verdict.detail -eq 'grantSatisfied') { 'Allowed - {0} satisfied' -f ($Verdict.requiredControls -join ', ') }
        else { 'Allowed' }
        $Row.pass = [bool]$Verdict.meetsExpectation
        $Row.requiredControls = @($Verdict.requiredControls)
        $Row.blockedBy = @($Verdict.blockedBy)
        $Row.reportOnlyWouldStop = @($Verdict.reportOnlyWouldStop)
        $Row.policies = @($Verdict.policies | Where-Object { $_.policyApplies })
        if ($Row.pass) { $Row.missingControl = '' }
        $Rows.Add($Row)
    }

    [PSCustomObject]@{
        identities = [PSCustomObject]$Identities
        candidates = [PSCustomObject]@{ admins = @($AdminCandidates) }
        country    = $Country
        situations = @($Rows)
        excluded   = @($Excluded)
        summary    = [PSCustomObject]@{
            total        = $Rows.Count
            protected    = @($Rows | Where-Object { $_.pass -eq $true }).Count
            unprotected  = @($Rows | Where-Object { $_.pass -eq $false }).Count
            notEvaluated = @($Rows | Where-Object { $null -eq $_.pass }).Count
            reportOnly   = @($Rows | Where-Object { $_.pass -eq $false -and @($_.reportOnlyWouldStop).Count -gt 0 }).Count
            unlicensed   = $Excluded.Count
        }
    }
}
