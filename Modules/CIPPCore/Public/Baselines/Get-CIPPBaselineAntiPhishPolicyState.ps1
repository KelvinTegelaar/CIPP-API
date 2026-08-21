function Get-CIPPBaselineAntiPhishPolicyState {
    <#
    .SYNOPSIS
        Prepare hook for AntiPhishPolicy: the policy and the rule that scopes it.
    .DESCRIPTION
        The graded property set depends on LICENSING, which is why this cannot be a static
        template. With Defender for Office 365 (ATP_ENTERPRISE) the classic standard grades 23
        properties including impersonation and mailbox-intelligence protection; without it,
        only the 8 that exist on a plain Exchange tenant. Grading the full set on an
        unlicensed tenant reports drift for settings that cannot be configured there.

        Note this is a per-tenant CAPABILITY check, not the standard's licence gate: the
        standard still runs on an unlicensed tenant, just against the smaller set. That is why
        requiredCapabilities carries only the Exchange group.
    .FUNCTIONALITY
        Internal
    #>
    [CmdletBinding()]
    param(
        $Item,
        $TenantFilter
    )

    $Policies = @(Get-CIPPBaselineCacheRows -TenantFilter $TenantFilter -Type 'ExoAntiPhishPolicies')
    if ($Policies.Count -eq 0) { return @{ Current = $null } }
    $Rules = @(Get-CIPPBaselineCacheRows -TenantFilter $TenantFilter -Type 'ExoAntiPhishRules' -CollectorType 'ExoAntiPhishPolicies')
    $AcceptedDomains = @((Get-CIPPBaselineCacheRows -TenantFilter $TenantFilter -Type 'ExoAcceptedDomains').Name | Where-Object { $_ } | Sort-Object)

    $Capabilities = $(try { Get-CIPPTenantCapabilities -TenantFilter $TenantFilter } catch { $null })
    $MDOLicensed = $Capabilities.ATP_ENTERPRISE -eq $true

    $Configured = if ([string]::IsNullOrWhiteSpace("$($Item.Variables.name)")) { 'CIPP Default Anti-Phishing Policy' } else { "$($Item.Variables.name)" }
    $PolicyCandidates = @($Configured, 'CIPP Default Anti-Phishing Policy', 'Default Anti-Phishing Policy')
    $ExistingPolicy = @($Policies | Where-Object { $PolicyCandidates -contains "$($_.Name)" }) | Select-Object -First 1
    $PolicyName = if ($ExistingPolicy.Name) { "$($ExistingPolicy.Name)" } else { $Configured }

    $DesiredRuleName = "$PolicyName Rule"
    $RuleCandidates = @($DesiredRuleName, 'CIPP Default Anti-Phishing Rule', 'CIPP Default Anti-Phishing Policy')
    $ExistingRule = @($Rules | Where-Object { $RuleCandidates -contains "$($_.Name)" }) | Select-Object -First 1
    $RuleName = if ($ExistingRule.Name) { "$($ExistingRule.Name)" } else { $DesiredRuleName }

    $Policy = @($Policies | Where-Object { "$($_.Name)" -eq $PolicyName }) | Select-Object -First 1
    $Rule = @($Rules | Where-Object { "$($_.Name)" -eq $RuleName }) | Select-Object -First 1
    $V = $Item.Variables

    # The eight properties every tenant has.
    $Expected = [PSCustomObject]@{
        name                         = $PolicyName
        enabled                      = $true
        enableSpoofIntelligence      = $true
        enableFirstContactSafetyTips = [bool]($V.EnableFirstContactSafetyTips -eq $true)
        enableUnauthenticatedSender  = $true
        enableViaTag                 = $true
        authenticationFailAction     = "$($V.AuthenticationFailAction)"
        spoofQuarantineTag           = "$($V.SpoofQuarantineTag)"
    }
    $Current = [PSCustomObject]@{
        name                         = "$($Policy.Name)"
        enabled                      = [bool]$Policy.Enabled
        enableSpoofIntelligence      = [bool]$Policy.EnableSpoofIntelligence
        enableFirstContactSafetyTips = [bool]$Policy.EnableFirstContactSafetyTips
        enableUnauthenticatedSender  = [bool]$Policy.EnableUnauthenticatedSender
        enableViaTag                 = [bool]$Policy.EnableViaTag
        authenticationFailAction     = "$($Policy.AuthenticationFailAction)"
        spoofQuarantineTag           = "$($Policy.SpoofQuarantineTag)"
    }

    if ($MDOLicensed) {
        $MdoExpected = [ordered]@{
            phishThresholdLevel                 = "$($V.PhishThresholdLevel)"
            enableMailboxIntelligence           = $true
            enableMailboxIntelligenceProtection = $true
            enableSimilarUsersSafetyTips        = [bool]($V.EnableSimilarUsersSafetyTips -eq $true)
            enableSimilarDomainsSafetyTips      = [bool]($V.EnableSimilarDomainsSafetyTips -eq $true)
            enableUnusualCharactersSafetyTips   = [bool]($V.EnableUnusualCharactersSafetyTips -eq $true)
            mailboxIntelligenceProtectionAction = "$($V.MailboxIntelligenceProtectionAction)"
            mailboxIntelligenceQuarantineTag    = "$($V.MailboxIntelligenceQuarantineTag)"
            targetedUserProtectionAction        = "$($V.TargetedUserProtectionAction)"
            targetedUserQuarantineTag           = "$($V.TargetedUserQuarantineTag)"
            targetedDomainProtectionAction      = "$($V.TargetedDomainProtectionAction)"
            targetedDomainQuarantineTag         = "$($V.TargetedDomainQuarantineTag)"
            enableTargetedDomainsProtection     = $true
            enableTargetedUserProtection        = $true
            enableOrganizationDomainsProtection = $true
        }
        $MdoCurrent = [ordered]@{
            phishThresholdLevel                 = "$($Policy.PhishThresholdLevel)"
            enableMailboxIntelligence           = [bool]$Policy.EnableMailboxIntelligence
            enableMailboxIntelligenceProtection = [bool]$Policy.EnableMailboxIntelligenceProtection
            enableSimilarUsersSafetyTips        = [bool]$Policy.EnableSimilarUsersSafetyTips
            enableSimilarDomainsSafetyTips      = [bool]$Policy.EnableSimilarDomainsSafetyTips
            enableUnusualCharactersSafetyTips   = [bool]$Policy.EnableUnusualCharactersSafetyTips
            mailboxIntelligenceProtectionAction = "$($Policy.MailboxIntelligenceProtectionAction)"
            mailboxIntelligenceQuarantineTag    = "$($Policy.MailboxIntelligenceQuarantineTag)"
            targetedUserProtectionAction        = "$($Policy.TargetedUserProtectionAction)"
            targetedUserQuarantineTag           = "$($Policy.TargetedUserQuarantineTag)"
            targetedDomainProtectionAction      = "$($Policy.TargetedDomainProtectionAction)"
            targetedDomainQuarantineTag         = "$($Policy.TargetedDomainQuarantineTag)"
            enableTargetedDomainsProtection     = [bool]$Policy.EnableTargetedDomainsProtection
            enableTargetedUserProtection        = [bool]$Policy.EnableTargetedUserProtection
            enableOrganizationDomainsProtection = [bool]$Policy.EnableOrganizationDomainsProtection
        }
        foreach ($Key in $MdoExpected.Keys) { $Expected | Add-Member -NotePropertyName $Key -NotePropertyValue $MdoExpected[$Key] }
        foreach ($Key in $MdoCurrent.Keys) { $Current | Add-Member -NotePropertyName $Key -NotePropertyValue $MdoCurrent[$Key] }
    }

    $Expected | Add-Member -NotePropertyName 'rule' -NotePropertyValue ([PSCustomObject]@{
            name = $RuleName; policy = $PolicyName; priority = 0; recipientDomainIs = @($AcceptedDomains)
        })
    $Current | Add-Member -NotePropertyName 'rule' -NotePropertyValue ([PSCustomObject]@{
            name              = "$($Rule.Name)"
            policy            = "$($Rule.AntiPhishPolicy)"
            priority          = $(if ($null -eq $Rule.Priority) { -1 } else { [int]$Rule.Priority })
            recipientDomainIs = @(@($Rule.RecipientDomainIs) | Where-Object { $_ } | Sort-Object)
        })

    $Current | Add-Member -NotePropertyName 'policyName' -NotePropertyValue $PolicyName
    $Current | Add-Member -NotePropertyName 'ruleName' -NotePropertyValue $RuleName
    $Current | Add-Member -NotePropertyName 'policyExists' -NotePropertyValue ([bool]$Policy)
    $Current | Add-Member -NotePropertyName 'ruleExists' -NotePropertyValue ([bool]$Rule)
    $Current | Add-Member -NotePropertyName 'ruleLinkedPolicy' -NotePropertyValue "$($Rule.AntiPhishPolicy)"
    $Current | Add-Member -NotePropertyName 'acceptedDomains' -NotePropertyValue @($AcceptedDomains)
    $Current | Add-Member -NotePropertyName 'mdoLicensed' -NotePropertyValue $MDOLicensed
    # DERIVED write params the static remediate spec cannot express. Same derivations as
    # the graded Expected above, so grade and write can never disagree - these fifteen
    # were graded but never written, drifting forever. Blank optional actions/tags are
    # omitted: sending an empty enum errors, and the operator has not expressed intent.
    $ExtraPolicyParams = [ordered]@{
        EnableMailboxIntelligence           = $true
        EnableMailboxIntelligenceProtection = $true
        EnableTargetedDomainsProtection     = $true
        EnableTargetedUserProtection        = $true
        EnableOrganizationDomainsProtection = $true
        EnableSimilarUsersSafetyTips        = [bool]($V.EnableSimilarUsersSafetyTips -eq $true)
        EnableSimilarDomainsSafetyTips      = [bool]($V.EnableSimilarDomainsSafetyTips -eq $true)
        EnableUnusualCharactersSafetyTips   = [bool]($V.EnableUnusualCharactersSafetyTips -eq $true)
    }
    if (-not [string]::IsNullOrWhiteSpace("$($V.PhishThresholdLevel)")) { $ExtraPolicyParams['PhishThresholdLevel'] = [int]"$($V.PhishThresholdLevel)" }
    foreach ($ActionParam in @('MailboxIntelligenceProtectionAction', 'MailboxIntelligenceQuarantineTag', 'TargetedUserProtectionAction', 'TargetedUserQuarantineTag', 'TargetedDomainProtectionAction', 'TargetedDomainQuarantineTag')) {
        if (-not [string]::IsNullOrWhiteSpace("$($V.$ActionParam)")) { $ExtraPolicyParams[$ActionParam] = "$($V.$ActionParam)" }
    }
    $Current | Add-Member -NotePropertyName 'extraPolicyParams' -NotePropertyValue ([PSCustomObject]$ExtraPolicyParams)

    @{ Expected = $Expected; Current = $Current }
}
