function Invoke-CIPPBaselineExoPolicyRule {
    <#
    .SYNOPSIS
        ExoPolicyRule executor: upserts a Defender policy and the rule that scopes it.
    .DESCRIPTION
        The Defender for Office families - Safe Attachments, Safe Links, Malware, Spam,
        Anti-Phish - are all one policy plus one rule that points at it, and every one of them
        has to decide New- versus Set- per object at run time. A rendered ExoRequest spec is
        fixed before it sees the tenant, so it cannot make that choice.

        The prepare hook has already resolved BOTH names, adopting whatever legacy name the
        tenant actually carries, and has computed the accepted-domain list the rule must scope
        to. Those arrive on -Current so the write targets exactly what the compare graded:
          policyName / ruleName - the resolved names
          policyExists / ruleExists - which verb to use
        Nothing here re-derives them, because a second resolution could disagree with the
        graded one and write to a different object than the row reports.

        Spec (fully rendered):
          policyCmdlet / ruleCmdlet - the noun pair, e.g. SafeAttachmentPolicy and
                                      SafeAttachmentRule. New- and Set- are prefixed here.
          policyParams / ruleParams - parameters minus the identity, which is added per verb.
          skipRule                  - set when the policy is a built-in that cannot carry a
                                      rule (the Spam family's Default policy).
    .FUNCTIONALITY
        Internal
    #>
    [CmdletBinding()]
    param(
        $Remediate,
        $TenantFilter,
        $Current
    )

    if (-not $Current) { throw 'ExoPolicyRule: the prepare hook produced no state to write from.' }

    $ToHashtable = {
        param($Object)
        $Table = @{}
        foreach ($Property in ($Object ?? [PSCustomObject]@{}).PSObject.Properties) { $Table[$Property.Name] = $Property.Value }
        $Table
    }

    $PolicyName = "$($Current.policyName)"
    if ([string]::IsNullOrWhiteSpace($PolicyName)) { throw 'ExoPolicyRule: the prepare hook resolved no policy name.' }

    $PolicyParams = & $ToHashtable $Remediate.policyParams
    if ($Current.policyExists -eq $true) {
        $PolicyParams['Identity'] = $PolicyName
        $null = New-ExoRequest -tenantid $TenantFilter -cmdlet "Set-$($Remediate.policyCmdlet)" -cmdParams $PolicyParams -UseSystemMailbox $true
    } else {
        $PolicyParams['Name'] = $PolicyName
        $null = New-ExoRequest -tenantid $TenantFilter -cmdlet "New-$($Remediate.policyCmdlet)" -cmdParams $PolicyParams -UseSystemMailbox $true
    }

    # A built-in policy owns its own scoping and rejects a rule pointing at it.
    if ($Remediate.skipRule -eq $true -or $Current.skipRule -eq $true) { return }

    $RuleName = "$($Current.ruleName)"
    if ([string]::IsNullOrWhiteSpace($RuleName)) { throw 'ExoPolicyRule: the prepare hook resolved no rule name.' }

    $RuleParams = & $ToHashtable $Remediate.ruleParams
    $RuleParams['RecipientDomainIs'] = @($Current.acceptedDomains)
    # Only re-point the rule when it is not already on the right policy - the classic
    # standards omitted the parameter otherwise.
    if ("$($Current.ruleLinkedPolicy)" -ne $PolicyName) { $RuleParams[$Remediate.policyCmdlet] = $PolicyName }

    if ($Current.ruleExists -eq $true) {
        $RuleParams['Identity'] = $RuleName
        $null = New-ExoRequest -tenantid $TenantFilter -cmdlet "Set-$($Remediate.ruleCmdlet)" -cmdParams $RuleParams -UseSystemMailbox $true
    } else {
        $RuleParams['Name'] = $RuleName
        $null = New-ExoRequest -tenantid $TenantFilter -cmdlet "New-$($Remediate.ruleCmdlet)" -cmdParams $RuleParams -UseSystemMailbox $true
    }
}
