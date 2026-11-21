function Invoke-CIPPBaselineSecOpsMailbox {
    <#
    .SYNOPSIS
        SecOpsMailbox executor: aligns the SecOps override policy and its rule.
    .DESCRIPTION
        Policy first, then the rule, each only when its leg drifted. The policy is created with
        the configured mailboxes, or enabled in place and given Add/Remove deltas
        (Set-SecOpsOverridePolicy speaks in deltas, not replacement lists). Invalid rules are
        removed before a missing valid rule is created, so the tenant never ends a run holding
        two. A valid rule is never touched.
    .FUNCTIONALITY
        Internal
    #>
    [CmdletBinding()]
    param(
        $Remediate,
        $TenantFilter,
        $Current
    )

    if (-not $Current) { throw 'SecOpsMailbox: the prepare hook produced no state to write from.' }

    $Wanted = @(@($Current.wantedMailboxes).Where({ $_ }))

    if ($Current.policyExists -ne $true) {
        $null = New-ExoRequest -tenantid $TenantFilter -cmdlet 'New-SecOpsOverridePolicy' -cmdParams @{ Name = 'SecOpsOverridePolicy'; SentTo = @($Wanted) }
    } else {
        $PolicyParams = @{ Identity = 'SecOpsOverridePolicy' }
        if ($Current.policyEnabled -ne $true) { $PolicyParams.Enabled = $true }
        # @($null).Count is 1: filter blanks so an ungraded list (strict mode off) is empty.
        $Missing = @(@($Current.missingMailboxes).Where({ $_ }))
        $Extra = @(@($Current.extraMailboxes).Where({ $_ }))
        if ($Missing.Count -gt 0) { $PolicyParams.AddSentTo = $Missing }
        if ($Extra.Count -gt 0) { $PolicyParams.RemoveSentTo = $Extra }
        if ($PolicyParams.Count -gt 1) {
            $null = New-ExoRequest -tenantid $TenantFilter -cmdlet 'Set-SecOpsOverridePolicy' -cmdParams $PolicyParams
        }
    }

    # The cache can be older than the tenant: a rule pending deletion may be gone by now. A failed
    # removal must not stop the missing valid rule from being created.
    foreach ($Identity in @(@($Current.invalidRules).Where({ $_ }))) {
        try {
            $null = New-ExoRequest -tenantid $TenantFilter -cmdlet 'Remove-ExoSecOpsOverrideRule' -cmdParams @{ Identity = "$Identity"; Confirm = $false }
        } catch {
            Write-LogMessage -API 'Baselines' -tenant $TenantFilter -message "Could not remove SecOps override rule $Identity, continuing: $($_.Exception.Message)" -Sev 'Warning'
        }
    }
    if ($Current.validRule -ne $true) {
        $null = New-ExoRequest -tenantid $TenantFilter -cmdlet 'New-ExoSecOpsOverrideRule' -cmdParams @{ Name = 'SecOpsOverrideRule'; Policy = 'SecOpsOverridePolicy' }
    }
    Write-LogMessage -API 'Baselines' -tenant $TenantFilter -message 'Aligned the SecOps mailbox overrides.' -Sev 'Info'
}
