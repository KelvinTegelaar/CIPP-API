function Get-CIPPCAWhatIfVerdict {
    <#
    .SYNOPSIS
        Turns a What If evaluation into an attacker's experience: blocked or allowed.
    .DESCRIPTION
        The API says which policies apply; it does not say whether the sign-in gets through.
    .FUNCTIONALITY
        Internal
    #>
    [CmdletBinding()]
    param(
        $Policies,
        $AttackerCanSatisfy,
        [string]$Expected = 'blocked'
    )

    $Satisfiable = @($AttackerCanSatisfy | Where-Object { $_ } | ForEach-Object { "$_".ToLower() })
    $Policies = @($Policies | Where-Object { $_ })

    $ControlsOf = {
        param($Policy)
        $List = [System.Collections.Generic.List[string]]::new()
        foreach ($Control in @($Policy.grantControls.builtInControls | Where-Object { $_ })) { $List.Add("$Control") }
        if ($Policy.grantControls.authenticationStrength) { $List.Add('authenticationStrength') }
        @($List)
    }

    $BlockedBy = [System.Collections.Generic.List[string]]::new()
    $ChallengedBy = [System.Collections.Generic.List[string]]::new()
    $SatisfiedPolicies = [System.Collections.Generic.List[string]]::new()
    $ReportOnlyWouldStop = [System.Collections.Generic.List[string]]::new()
    $RequiredControls = [System.Collections.Generic.List[string]]::new()
    $Rows = [System.Collections.Generic.List[object]]::new()

    foreach ($Policy in $Policies) {
        $Controls = & $ControlsOf $Policy
        $Operator = $(if ("$($Policy.grantControls.operator)") { "$($Policy.grantControls.operator)".ToUpper() } else { 'OR' })
        $Applies = $Policy.policyApplies -eq $true
        $State = "$($Policy.state)"
        $Met = @($Controls | Where-Object { $Satisfiable -contains $_.ToLower() })
        $Satisfied = if ($Controls.Count -eq 0) { $true } elseif ($Operator -eq 'AND') { $Met.Count -eq $Controls.Count } else { $Met.Count -gt 0 }
        $Blocks = $Controls -contains 'block'
        $ControlText = $Controls -join (' {0} ' -f $Operator.ToLower())

        $Result = if (-not $Applies) {
            $(if ($State -eq 'disabled') { 'Disabled - not evaluated' } else { 'Not applicable to this sign-in' })
        } elseif ($State -eq 'enabledForReportingButNotEnforced') {
            $(if ($Blocks -or -not $Satisfied) { 'Report-only - would have stopped this sign-in' } else { 'Report-only - would not have stopped this sign-in' })
        } elseif ($State -ne 'enabled') {
            'Disabled - not evaluated'
        } elseif ($Blocks) {
            'Blocks the sign-in'
        } elseif ($Controls.Count -eq 0) {
            'Applies session controls only'
        } elseif ($Satisfied) {
            "Requires $ControlText - satisfied by the attacker"
        } else {
            "Requires $ControlText - stops the attacker"
        }

        $Rows.Add([PSCustomObject]@{
                displayName   = "$($Policy.displayName)"
                state         = $State
                policyApplies = $Applies
                controls      = @($Controls)
                operator      = $Operator
                result        = $Result
            })

        if (-not $Applies) { continue }
        if ($State -eq 'enabledForReportingButNotEnforced') {
            if ($Blocks -or -not $Satisfied) { $ReportOnlyWouldStop.Add("$($Policy.displayName)") }
            continue
        }
        if ($State -ne 'enabled') { continue }
        if ($Blocks) { $BlockedBy.Add("$($Policy.displayName)"); continue }
        if ($Controls.Count -eq 0) { continue }
        foreach ($Control in $Controls) {
            if (-not $RequiredControls.Contains($Control)) { $RequiredControls.Add($Control) }
        }
        if ($Satisfied) { $SatisfiedPolicies.Add("$($Policy.displayName)") } else { $ChallengedBy.Add("$($Policy.displayName)") }
    }

    $Verdict = if ($BlockedBy.Count -gt 0 -or $ChallengedBy.Count -gt 0) { 'blocked' } else { 'allowed' }
    $Detail = if ($BlockedBy.Count -gt 0) { 'blockedByPolicy' }
    elseif ($ChallengedBy.Count -gt 0) { 'challenged' }
    elseif ($SatisfiedPolicies.Count -gt 0) { 'grantSatisfied' }
    else { 'noPolicy' }

    $RequiresMfa = ($RequiredControls -contains 'mfa') -or ($RequiredControls -contains 'authenticationStrength')
    $RequiresPhishingResistant = $RequiredControls -contains 'authenticationStrength'
    $MeetsExpectation = switch ("$Expected".ToLower()) {
        'mfa' { $Verdict -eq 'blocked' -or $RequiresMfa }
        'phishingresistant' { $Verdict -eq 'blocked' -or $RequiresPhishingResistant }
        default { $Verdict -eq 'blocked' }
    }

    [PSCustomObject]@{
        verdict             = $Verdict
        detail              = $Detail
        meetsExpectation    = [bool]$MeetsExpectation
        requiredControls    = @($RequiredControls)
        blockedBy           = @($BlockedBy)
        challengedBy        = @($ChallengedBy)
        satisfiedPolicies   = @($SatisfiedPolicies)
        reportOnlyWouldStop = @($ReportOnlyWouldStop)
        policies            = @($Rows)
        evaluatedCount      = $Policies.Count
    }
}
