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
    $ExistingPolicy = @(foreach ($Candidate in $PolicyCandidates) { $Policies.Where({ "$($_.Name)" -eq $Candidate }, 'First') })[0]
    $PolicyName = if ($ExistingPolicy.Name) { "$($ExistingPolicy.Name)" } else { $Configured }

    $DesiredRuleName = "$PolicyName Rule"
    $RuleCandidates = @($DesiredRuleName, 'CIPP Default Anti-Phishing Rule', 'CIPP Default Anti-Phishing Policy')
    # A rule made in the Defender portal shares the policy's name, so the link is matched first
    $LinkedRules = $Rules.Where({ "$($_.AntiPhishPolicy)" -eq $PolicyName })
    $ExistingRule = @($LinkedRules.Where({ $RuleCandidates -contains "$($_.Name)" }); $LinkedRules; $Rules.Where({ $RuleCandidates -contains "$($_.Name)" }))[0]
    $RuleName = if ($ExistingRule.Name) { "$($ExistingRule.Name)" } else { $DesiredRuleName }

    $Policy = @($Policies.Where({ "$($_.Name)" -eq $PolicyName })) | Select-Object -First 1
    $Rule = @($Rules.Where({ "$($_.Name)" -eq $RuleName })) | Select-Object -First 1
    $V = $Item.Variables

    # Get-AntiPhishPolicy only populates Enabled for the built-in default policy; on a custom policy
    # the active state lives on the rule's State (see Invoke-ListAntiPhishingFilters). Fall back to
    # the policy value so the built-in default policy stays correct.
    $PolicyEnabled = if ($null -ne $Rule.State) { $Rule.State -eq 'Enabled' } else { [bool]$Policy.Enabled }

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
        enabled                      = $PolicyEnabled
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
        foreach ($Key in $MdoExpected.Keys) { $Expected.PSObject.Properties.Remove($Key); $Expected.PSObject.Properties.Add([psnoteproperty]::new($Key, $MdoExpected[$Key])) }
        foreach ($Key in $MdoCurrent.Keys) { $Current.PSObject.Properties.Remove($Key); $Current.PSObject.Properties.Add([psnoteproperty]::new($Key, $MdoCurrent[$Key])) }
    }

    $Expected.PSObject.Properties.Remove('rule'); $Expected.PSObject.Properties.Add([psnoteproperty]::new('rule', ([PSCustomObject]@{
            name = $RuleName; policy = $PolicyName; priority = 0; recipientDomainIs = @($AcceptedDomains)
        })))
    $Current.PSObject.Properties.Remove('rule'); $Current.PSObject.Properties.Add([psnoteproperty]::new('rule', ([PSCustomObject]@{
            name              = "$($Rule.Name)"
            policy            = "$($Rule.AntiPhishPolicy)"
            priority          = $(if ($null -eq $Rule.Priority) { -1 } else { [int]$Rule.Priority })
            recipientDomainIs = @(@($Rule.RecipientDomainIs) | Where-Object { $_ } | Sort-Object)
        })))

    $Current.PSObject.Properties.Remove('policyName'); $Current.PSObject.Properties.Add([psnoteproperty]::new('policyName', $PolicyName))
    $Current.PSObject.Properties.Remove('ruleName'); $Current.PSObject.Properties.Add([psnoteproperty]::new('ruleName', $RuleName))
    $Current.PSObject.Properties.Remove('policyExists'); $Current.PSObject.Properties.Add([psnoteproperty]::new('policyExists', ([bool]$Policy)))
    $Current.PSObject.Properties.Remove('ruleExists'); $Current.PSObject.Properties.Add([psnoteproperty]::new('ruleExists', ([bool]$Rule)))
    $Current.PSObject.Properties.Remove('ruleLinkedPolicy'); $Current.PSObject.Properties.Add([psnoteproperty]::new('ruleLinkedPolicy', "$($Rule.AntiPhishPolicy)"))
    $Current.PSObject.Properties.Remove('acceptedDomains'); $Current.PSObject.Properties.Add([psnoteproperty]::new('acceptedDomains', @($AcceptedDomains)))
    $Current.PSObject.Properties.Remove('mdoLicensed'); $Current.PSObject.Properties.Add([psnoteproperty]::new('mdoLicensed', $MDOLicensed))
    # DERIVED write params the static remediate spec cannot express. Same derivations as
    # the graded Expected above, so grade and write can never disagree - these fifteen
    # were graded but never written, drifting forever. Blank optional actions/tags are
    # omitted: sending an empty enum errors, and the operator has not expressed intent.
    # Exchange rejects these on a tenant without Defender for Office 365.
    $ExtraPolicyParams = [ordered]@{}
    if ($MDOLicensed) {
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
    }
    $Current.PSObject.Properties.Remove('extraPolicyParams'); $Current.PSObject.Properties.Add([psnoteproperty]::new('extraPolicyParams', ([PSCustomObject]$ExtraPolicyParams)))

    @{ Expected = $Expected; Current = $Current }
}
