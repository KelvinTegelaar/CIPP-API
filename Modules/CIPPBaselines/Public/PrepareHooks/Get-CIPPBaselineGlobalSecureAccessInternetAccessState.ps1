function Get-CIPPBaselineGlobalSecureAccessInternetAccessState {
    <#
    .SYNOPSIS
        Prepare hook for the Internet Access standard: the Internet traffic profile plus the custom block page.
    .DESCRIPTION
        The Internet traffic profile is graded by the shared traffic profile hook. The custom block page
        is graded from the NetworkAccess cache only for what is configured: its state when set, its
        message when not blank. A needed write is carried for GraphBulkSweep as blockPageWrites (state and
        message) or blockPageStateWrites (state only). Graph requires a message to enable the page and
        refuses an empty one, so enabling without a configured message reuses the tenant's current
        message; disabling without one writes the state alone, which keeps the current message.

        With manageCustomRules on, the Custom bypass and Custom Acquire policies must hold exactly the
        configured destinations: a policy that differs has its rules deleted (ruleDeletes) and rebuilt
        (ruleCreates). Graded strictly, since the definition's subset compare would pass extra rules.
    .FUNCTIONALITY
        Internal
    #>
    [CmdletBinding()]
    param($Item, $TenantFilter)

    $State = Get-CIPPBaselineGlobalSecureAccessTrafficProfileState -Item $Item -TenantFilter $TenantFilter
    if ($null -eq $State.Current) { return $State }

    $BlockPageState = "$($Item.Variables.blockPageState.value ?? $Item.Variables.blockPageState)"
    $Message = "$($Item.Variables.blockMessage)"
    $BlockPageWrites = @()
    $BlockPageStateWrites = @()
    if ($BlockPageState -or $Message) {
        $Cached = @(New-CIPPDbRequest -TenantFilter $TenantFilter -Type 'NetworkAccess').Where({ $_ }, 'First')[0].customBlockPage
        $Drift = $false
        if ($BlockPageState) {
            $State.Expected | Add-Member -NotePropertyName 'blockPageState' -NotePropertyValue $BlockPageState
            $State.Current | Add-Member -NotePropertyName 'blockPageState' -NotePropertyValue "$($Cached.state)"
            $Drift = $BlockPageState -ne "$($Cached.state)"
        }
        if ($Message) {
            $State.Expected | Add-Member -NotePropertyName 'blockPageMessage' -NotePropertyValue $Message
            $State.Current | Add-Member -NotePropertyName 'blockPageMessage' -NotePropertyValue "$($Cached.message)"
            $Drift = $Drift -or $Message -cne "$($Cached.message)"
        }
        $WriteState = $BlockPageState ? $BlockPageState : ("$($Cached.state)" ? "$($Cached.state)" : 'enabled')
        $WriteMessage = $Message ? $Message : "$($Cached.message)"
        if ($Drift -and ($Message -or $WriteState -eq 'enabled')) {
            if ([string]::IsNullOrWhiteSpace($WriteMessage)) {
                return @{ Current = $null; ConfigError = $true; NoDataReason = 'enabling the custom block page needs a message, and the tenant has none yet; add a block page message' }
            }
            $BlockPageWrites = @([pscustomobject]@{ state = $WriteState; message = $WriteMessage })
        } elseif ($Drift) {
            $BlockPageStateWrites = @([pscustomobject]@{ state = $WriteState })
        }
    }
    $RuleDeletes = [System.Collections.Generic.List[object]]::new()
    $RuleCreates = [System.Collections.Generic.List[object]]::new()
    if ("$($Item.Variables.manageCustomRules)" -eq 'true') {
        $Internet = @(@(New-CIPPDbRequest -TenantFilter $TenantFilter -Type 'NetworkAccess').Where({ $_ }, 'First')[0].profiles).Where({ $_.trafficForwardingType -eq 'internet' -and -not $_.isCustomProfile }, 'First')[0]
        $Format = { param($Entries) @(@($Entries).Where({ $_.destination }).ForEach({ "$($_.destination) ($(if ($_.ports -eq '0-65535') { 'all ports' } else { "ports $($_.ports)" }), $($_.protocols))" })) }
        $Strict = [System.Collections.Generic.List[string]]::new()
        foreach ($Kind in @(
                @{ Key = 'customBypass'; Policy = 'Custom bypass'; Action = 'bypass' }
                @{ Key = 'customAcquire'; Policy = 'Custom Acquire'; Action = 'forward' }
            )) {
            $Link = @($Internet.policies).Where({ $_.policyName -eq $Kind.Policy }, 'First')[0]
            if (-not $Link -or $Link.rulesRead -ne $true) { return @{ Current = $null; NoDataReason = "could not read the Internet profile's $($Kind.Policy) rules" } }
            $Destinations = @(@($Item.Variables.($Kind.Key)).ForEach({ "$($_.value ?? $_)" -split ',' }).ForEach({ $_.Trim() }).Where({ $_ }))
            try {
                $Desired = @(ConvertTo-CIPPGSAForwardingRule -Destinations $Destinations -Action $Kind.Action -Ports "$($Item.Variables.("$($Kind.Key)Ports"))")
            } catch {
                return @{ Current = $null; ConfigError = $true; NoDataReason = "$($Kind.Policy): $($_.Exception.Message)" }
            }
            $ExpectedEntries = @(& $Format (ConvertFrom-CIPPGSAForwardingRule -Rules $Desired))
            $CurrentEntries = @(& $Format $Link.rules)
            $State.Expected | Add-Member -NotePropertyName $Kind.Key -NotePropertyValue ([string[]]$ExpectedEntries)
            $State.Current | Add-Member -NotePropertyName $Kind.Key -NotePropertyValue ([string[]]$CurrentEntries)
            $Strict.Add($Kind.Key)
            if (($ExpectedEntries -join "`n") -ne ($CurrentEntries -join "`n")) {
                foreach ($RuleId in @($Link.ruleIds).Where({ $_ })) { $RuleDeletes.Add([pscustomobject]@{ policyId = $Link.policyId; id = $RuleId }) }
                foreach ($Rule in $Desired) { $RuleCreates.Add([pscustomobject]@{ policyId = $Link.policyId; rule = $Rule }) }
            }
        }
        $State.StrictCompare = @($Strict)
    }
    $State.Current | Add-Member -NotePropertyName 'ruleDeletes' -NotePropertyValue @($RuleDeletes)
    $State.Current | Add-Member -NotePropertyName 'ruleCreates' -NotePropertyValue @($RuleCreates)
    $State.Current | Add-Member -NotePropertyName 'blockPageWrites' -NotePropertyValue $BlockPageWrites
    $State.Current | Add-Member -NotePropertyName 'blockPageStateWrites' -NotePropertyValue $BlockPageStateWrites
    $State
}
