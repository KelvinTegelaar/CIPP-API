function Get-CIPPBaselineSecOpsMailboxState {
    <#
    .SYNOPSIS
        Prepare hook for SecOpsMailbox: the SecOps override policy and its rule (Defender
        advanced delivery).
    .DESCRIPTION
        Two legs, graded separately so the drift row names the broken one: the override POLICY
        must exist enabled and list the configured mailboxes, and exactly one override RULE
        must be valid - Mode Enforce, not disabled, bound to the policy.

        Microsoft documents that Get-ExoSecOpsOverrideRule should return one rule but can also
        return one pending deletion, and that the fix is to remove the invalid rule. Every rule
        other than the first valid one is graded as invalid and its identity carried for the
        executor to remove.

        The mailbox list is additive by default; RemoveExtraMailboxes opts into strict ownership
        where mailboxes outside the configured set grade as removals.
    .FUNCTIONALITY
        Internal
    #>
    [CmdletBinding()]
    param(
        $Item,
        $TenantFilter
    )

    $Policies = @(Get-CIPPBaselineCacheRows -TenantFilter $TenantFilter -Type 'ExoSecOpsOverridePolicy' -CollectorType 'ExoSecOpsConfig')
    $Rules = @(Get-CIPPBaselineCacheRows -TenantFilter $TenantFilter -Type 'ExoSecOpsOverrideRule' -CollectorType 'ExoSecOpsConfig')
    if ($Policies.Count -eq 0 -and $Rules.Count -eq 0 -and -not (Test-CIPPBaselineCacheCollected -TenantFilter $TenantFilter -Type 'ExoSecOpsOverridePolicy')) {
        return @{ Current = $null }
    }

    $Wanted = [System.Collections.Generic.List[string]]::new()
    foreach ($Entry in @($Item.Variables.SentTo)) {
        $Address = "$($Entry.value ?? $Entry)".Trim()
        if ([string]::IsNullOrWhiteSpace($Address)) { continue }
        $Address = $Address.ToLowerInvariant()
        if ($Address -notmatch '@') { return @{ Current = $null; NoDataReason = "the configured address '$Address' is not a valid email address"; ConfigError = $true } }
        if (-not $Wanted.Contains($Address)) { $Wanted.Add($Address) }
    }
    if ($Wanted.Count -eq 0) { return @{ Current = $null; ConfigError = $true } }
    $RemoveExtra = [bool]($Item.Variables.RemoveExtraMailboxes -eq $true)

    # Microsoft names the policy SecOpsOverridePolicy whatever name it is created with.
    $Policy = $Policies.Where({ "$($_.Name)" -eq 'SecOpsOverridePolicy' }, 'First')[0]
    if (-not $Policy -and $Policies.Count -gt 0) { $Policy = $Policies[0] }
    $PolicyKeys = @("$($Policy.ExternalIdentity)", "$($Policy.Identity)", "$($Policy.Name)").Where({ $_ })

    $CurrentSentTo = @(@($Policy.SentTo).ForEach({ "$_".ToLowerInvariant() }).Where({ $_ }))
    $MissingMailboxes = @($Wanted.Where({ $CurrentSentTo -notcontains $_ }) | Sort-Object)
    $ExtraMailboxes = @()
    if ($RemoveExtra) { $ExtraMailboxes = @($CurrentSentTo.Where({ -not $Wanted.Contains($_) }) | Sort-Object) }

    $ValidRule = $null
    $InvalidRules = [System.Collections.Generic.List[string]]::new()
    foreach ($Rule in $Rules) {
        $IsValid = $Policy -and "$($Rule.Mode)" -eq 'Enforce' -and $Rule.Disabled -ne $true -and $PolicyKeys -contains "$($Rule.Policy)"
        if ($IsValid -and -not $ValidRule) { $ValidRule = $Rule } else { $InvalidRules.Add("$($Rule.Identity)") }
    }

    $Expected = [PSCustomObject]@{
        policyEnabled    = $true
        missingMailboxes = @()
        validRule        = $true
        invalidRules     = @()
    }
    $Current = [PSCustomObject]@{
        policyEnabled    = [bool]($Policy -and $Policy.Enabled -eq $true)
        missingMailboxes = @($MissingMailboxes)
        validRule        = [bool]$ValidRule
        invalidRules     = @($InvalidRules)
    }
    if ($RemoveExtra) {
        $Expected | Add-Member -NotePropertyName 'extraMailboxes' -NotePropertyValue @()
        $Current | Add-Member -NotePropertyName 'extraMailboxes' -NotePropertyValue @($ExtraMailboxes)
    }
    # Carried for the executor.
    $Current | Add-Member -NotePropertyName 'policyExists' -NotePropertyValue ([bool]$Policy)
    $Current | Add-Member -NotePropertyName 'wantedMailboxes' -NotePropertyValue @($Wanted)

    @{ Expected = $Expected; Current = $Current }
}
