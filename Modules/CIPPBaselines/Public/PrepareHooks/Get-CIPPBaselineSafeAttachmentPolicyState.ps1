function Get-CIPPBaselineSafeAttachmentPolicyState {
    <#
    .SYNOPSIS
        Prepare hook for SafeAttachmentPolicy: the policy and the rule that scopes it.
    .DESCRIPTION
        Three things here cannot be expressed declaratively:

        Legacy name adoption. The policy is whichever of the configured name, 'CIPP Default
        Safe Attachment Policy' or 'Default Safe Attachment Policy' the tenant already has -
        first match wins, and the found name becomes the name everything else is keyed on. A
        read filter takes one fixed value and cannot express 'whichever of these exists'.
        Adopting matters: without it a tenant carrying the older name gets a SECOND policy
        rather than an update.

        Rule scoping. The rule must list every accepted domain, which is tenant state rather
        than a configured value, so no %token% can render it.

        Rule grading. The classic standard remediated the rule independently of the policy but
        reported only the policy. Here the rule joins the compare, so a rule-only deviation
        still triggers the write - which is what the classic did - and is visible in the row.

        The resolved names and existence flags ride along on Current for the executor, so the
        write targets exactly what was graded rather than re-resolving and possibly disagreeing.
    .FUNCTIONALITY
        Internal
    #>
    [CmdletBinding()]
    param(
        $Item,
        $TenantFilter
    )

    $Policies = @(Get-CIPPBaselineCacheRows -TenantFilter $TenantFilter -Type 'ExoSafeAttachmentPolicies')
    if ($Policies.Count -eq 0) { return @{ Current = $null } }
    $Rules = @(Get-CIPPBaselineCacheRows -TenantFilter $TenantFilter -Type 'ExoSafeAttachmentRules' -CollectorType 'ExoSafeAttachmentPolicies')
    $AcceptedDomains = @((Get-CIPPBaselineCacheRows -TenantFilter $TenantFilter -Type 'ExoAcceptedDomains').Name | Where-Object { $_ } | Sort-Object)

    $Configured = if ([string]::IsNullOrWhiteSpace("$($Item.Variables.name)")) { 'CIPP Default Safe Attachment Policy' } else { "$($Item.Variables.name)" }
    $PolicyCandidates = @($Configured, 'CIPP Default Safe Attachment Policy', 'Default Safe Attachment Policy')
    $ExistingPolicy = @($Policies | Where-Object { $PolicyCandidates -contains "$($_.Name)" }) | Select-Object -First 1
    $PolicyName = if ($ExistingPolicy.Name) { "$($ExistingPolicy.Name)" } else { $Configured }

    $DesiredRuleName = "$PolicyName Rule"
    $RuleCandidates = @($DesiredRuleName, 'CIPP Default Safe Attachment Rule', 'CIPP Default Safe Attachment Policy')
    $ExistingRule = @($Rules | Where-Object { $RuleCandidates -contains "$($_.Name)" }) | Select-Object -First 1
    $RuleName = if ($ExistingRule.Name) { "$($ExistingRule.Name)" } else { $DesiredRuleName }

    $Policy = @($Policies | Where-Object { "$($_.Name)" -eq $PolicyName }) | Select-Object -First 1
    $Rule = @($Rules | Where-Object { "$($_.Name)" -eq $RuleName }) | Select-Object -First 1

    $Expected = [PSCustomObject]@{
        name          = $PolicyName
        enable        = $true
        action        = "$($Item.Variables.SafeAttachmentAction)"
        quarantineTag = "$($Item.Variables.QuarantineTag)"
        redirect      = [bool]($Item.Variables.Redirect -eq $true)
        rule          = [PSCustomObject]@{
            name              = $RuleName
            policy            = $PolicyName
            priority          = 0
            recipientDomainIs = @($AcceptedDomains)
        }
    }
    $Current = [PSCustomObject]@{
        name          = "$($Policy.Name)"
        enable        = [bool]$Policy.Enable
        action        = "$($Policy.Action)"
        quarantineTag = "$($Policy.QuarantineTag)"
        redirect      = [bool]$Policy.Redirect
        rule          = [PSCustomObject]@{
            name              = "$($Rule.Name)"
            policy            = "$($Rule.SafeAttachmentPolicy)"
            priority          = $(if ($null -eq $Rule.Priority) { -1 } else { [int]$Rule.Priority })
            recipientDomainIs = @(@($Rule.RecipientDomainIs) | Where-Object { $_ } | Sort-Object)
        }
    }

    # RedirectAddress is only graded when the operator supplied one, matching the classic
    # '($null -eq $Settings.RedirectAddress) -or ...' test.
    if (-not [string]::IsNullOrWhiteSpace("$($Item.Variables.RedirectAddress)")) {
        $Expected | Add-Member -NotePropertyName 'redirectAddress' -NotePropertyValue "$($Item.Variables.RedirectAddress)"
        $Current | Add-Member -NotePropertyName 'redirectAddress' -NotePropertyValue "$($Policy.RedirectAddress)"
    }

    # Carried for the executor, not graded - the engine projects Current to the Expected keys.
    $Current | Add-Member -NotePropertyName 'policyName' -NotePropertyValue $PolicyName
    $Current | Add-Member -NotePropertyName 'ruleName' -NotePropertyValue $RuleName
    $Current | Add-Member -NotePropertyName 'policyExists' -NotePropertyValue ([bool]$Policy)
    $Current | Add-Member -NotePropertyName 'ruleExists' -NotePropertyValue ([bool]$Rule)
    $Current | Add-Member -NotePropertyName 'ruleLinkedPolicy' -NotePropertyValue "$($Rule.SafeAttachmentPolicy)"
    $Current | Add-Member -NotePropertyName 'acceptedDomains' -NotePropertyValue @($AcceptedDomains)

    @{ Expected = $Expected; Current = $Current }
}
