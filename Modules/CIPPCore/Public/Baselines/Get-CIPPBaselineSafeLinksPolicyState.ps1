function Get-CIPPBaselineSafeLinksPolicyState {
    <#
    .SYNOPSIS
        Prepare hook for SafeLinksPolicy: the policy and the rule that scopes it.
    .DESCRIPTION
        Same shape as the other Defender families - legacy name adoption, accepted-domain rule
        scoping, and the rule graded alongside the policy so a rule-only deviation still
        triggers the write.

        Two quirks specific to this family, both carried verbatim:
        the desired rule name uses an UNDERSCORE ("<policy>_Rule"), while the older CIPP name
        used a space, so both are candidates; and DoNotRewriteUrls compares against an empty
        list when nothing is configured, matching the classic '?? @()'.
    .FUNCTIONALITY
        Internal
    #>
    [CmdletBinding()]
    param(
        $Item,
        $TenantFilter
    )

    $Policies = @(Get-CIPPBaselineCacheRows -TenantFilter $TenantFilter -Type 'ExoSafeLinksPolicies')
    if ($Policies.Count -eq 0) { return @{ Current = $null } }
    $Rules = @(Get-CIPPBaselineCacheRows -TenantFilter $TenantFilter -Type 'ExoSafeLinksRules' -CollectorType 'ExoSafeLinksPolicies')
    $AcceptedDomains = @((Get-CIPPBaselineCacheRows -TenantFilter $TenantFilter -Type 'ExoAcceptedDomains').Name | Where-Object { $_ } | Sort-Object)

    $Configured = if ([string]::IsNullOrWhiteSpace("$($Item.Variables.name)")) { 'CIPP Default SafeLinks Policy' } else { "$($Item.Variables.name)" }
    $PolicyCandidates = @($Configured, 'CIPP Default SafeLinks Policy', 'Default SafeLinks Policy')
    $ExistingPolicy = @($Policies | Where-Object { $PolicyCandidates -contains "$($_.Name)" }) | Select-Object -First 1
    $PolicyName = if ($ExistingPolicy.Name) { "$($ExistingPolicy.Name)" } else { $Configured }

    $DesiredRuleName = "$($PolicyName)_Rule"
    $RuleCandidates = @($DesiredRuleName, "$PolicyName Rule", 'CIPP Default SafeLinks Rule', 'CIPP Default SafeLinks Policy')
    $ExistingRule = @($Rules | Where-Object { $RuleCandidates -contains "$($_.Name)" }) | Select-Object -First 1
    $RuleName = if ($ExistingRule.Name) { "$($ExistingRule.Name)" } else { $DesiredRuleName }

    $Policy = @($Policies | Where-Object { "$($_.Name)" -eq $PolicyName }) | Select-Object -First 1
    $Rule = @($Rules | Where-Object { "$($_.Name)" -eq $RuleName }) | Select-Object -First 1

    $DoNotRewrite = @(@($Item.Variables.DoNotRewriteUrls) | Where-Object { $_ } | Sort-Object)

    $Expected = [PSCustomObject]@{
        name                       = $PolicyName
        enableSafeLinksForEmail    = $true
        enableSafeLinksForTeams    = $true
        enableSafeLinksForOffice   = $true
        trackClicks                = $true
        scanUrls                   = $true
        enableForInternalSenders   = $true
        deliverMessageAfterScan    = $true
        allowClickThrough          = [bool]($Item.Variables.AllowClickThrough -eq $true)
        disableUrlRewrite          = [bool]($Item.Variables.DisableUrlRewrite -eq $true)
        enableOrganizationBranding = [bool]($Item.Variables.EnableOrganizationBranding -eq $true)
        doNotRewriteUrls           = @($DoNotRewrite)
        rule                       = [PSCustomObject]@{
            name              = $RuleName
            policy            = $PolicyName
            priority          = 0
            recipientDomainIs = @($AcceptedDomains)
        }
    }
    $Current = [PSCustomObject]@{
        name                       = "$($Policy.Name)"
        enableSafeLinksForEmail    = [bool]$Policy.EnableSafeLinksForEmail
        enableSafeLinksForTeams    = [bool]$Policy.EnableSafeLinksForTeams
        enableSafeLinksForOffice   = [bool]$Policy.EnableSafeLinksForOffice
        trackClicks                = [bool]$Policy.TrackClicks
        scanUrls                   = [bool]$Policy.ScanUrls
        enableForInternalSenders   = [bool]$Policy.EnableForInternalSenders
        deliverMessageAfterScan    = [bool]$Policy.DeliverMessageAfterScan
        allowClickThrough          = [bool]$Policy.AllowClickThrough
        disableUrlRewrite          = [bool]$Policy.DisableUrlRewrite
        enableOrganizationBranding = [bool]$Policy.EnableOrganizationBranding
        doNotRewriteUrls           = @(@($Policy.DoNotRewriteUrls) | Where-Object { $_ } | Sort-Object)
        rule                       = [PSCustomObject]@{
            name              = "$($Rule.Name)"
            policy            = "$($Rule.SafeLinksPolicy)"
            priority          = $(if ($null -eq $Rule.Priority) { -1 } else { [int]$Rule.Priority })
            recipientDomainIs = @(@($Rule.RecipientDomainIs) | Where-Object { $_ } | Sort-Object)
        }
    }

    $Current | Add-Member -NotePropertyName 'policyName' -NotePropertyValue $PolicyName
    $Current | Add-Member -NotePropertyName 'ruleName' -NotePropertyValue $RuleName
    $Current | Add-Member -NotePropertyName 'policyExists' -NotePropertyValue ([bool]$Policy)
    $Current | Add-Member -NotePropertyName 'ruleExists' -NotePropertyValue ([bool]$Rule)
    $Current | Add-Member -NotePropertyName 'ruleLinkedPolicy' -NotePropertyValue "$($Rule.SafeLinksPolicy)"
    $Current | Add-Member -NotePropertyName 'acceptedDomains' -NotePropertyValue @($AcceptedDomains)

    @{ Expected = $Expected; Current = $Current }
}
