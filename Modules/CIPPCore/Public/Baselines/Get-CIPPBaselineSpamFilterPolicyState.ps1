function Get-CIPPBaselineSpamFilterPolicyState {
    <#
    .SYNOPSIS
        Prepare hook for SpamFilterPolicy: the content filter policy and its rule.
    .DESCRIPTION
        The largest of the Defender families - thirty graded properties, several of them
        derived rather than configured. Three things carried verbatim from the classic
        standard:

        Derived On/Off values. Eight settings are switches in the UI but 'On'/'Off' strings in
        Exchange, and a further nine are hardcoded constants the standard always enforces.

        The Default policy has no rule. When the adopted policy is the built-in 'Default',
        Exchange owns its scoping and rejects a rule pointing at it, so the rule is neither
        graded nor written - the classic guarded its rule block with '-and -not
        $IsDefaultPolicy'. That is signalled to the executor as skipRule.

        Conditional list grading. The language and region block lists are only compared when
        their Enable switch is on, and allowed-sender domains treat 'both empty' as equal -
        the classic's long null-and-count expression.
    .FUNCTIONALITY
        Internal
    #>
    [CmdletBinding()]
    param(
        $Item,
        $TenantFilter
    )

    $Policies = @(Get-CIPPBaselineCacheRows -TenantFilter $TenantFilter -Type 'ExoHostedContentFilterPolicy')
    if ($Policies.Count -eq 0) { return @{ Current = $null } }
    $Rules = @(Get-CIPPBaselineCacheRows -TenantFilter $TenantFilter -Type 'ExoHostedContentFilterRule')
    $AcceptedDomains = @((Get-CIPPBaselineCacheRows -TenantFilter $TenantFilter -Type 'ExoAcceptedDomains').Name | Where-Object { $_ } | Sort-Object)

    $V = $Item.Variables
    $Configured = if ([string]::IsNullOrWhiteSpace("$($V.name)")) { 'CIPP Default Spam Filter Policy' } else { "$($V.name)" }
    $PolicyCandidates = @($Configured, 'Default Spam Filter Policy', 'Default')
    $ExistingPolicy = @($Policies | Where-Object { $PolicyCandidates -contains "$($_.Name)" }) | Select-Object -First 1
    $PolicyName = if ($ExistingPolicy.Name) { "$($ExistingPolicy.Name)" } else { $Configured }
    $IsDefaultPolicy = $PolicyName -eq 'Default'

    $Policy = @($Policies | Where-Object { "$($_.Name)" -eq $PolicyName }) | Select-Object -First 1
    # The classic keys the rule on the POLICY name, not a "<policy> Rule" name.
    $Rule = @($Rules | Where-Object { "$($_.Name)" -eq $PolicyName }) | Select-Object -First 1

    $OnOff = { param($Value) if ($Value -eq $true) { 'On' } else { 'Off' } }
    $SplitList = { param($Value, $Case)
        $Items = @(@($Value) | ForEach-Object { "$_" -split ',' } | ForEach-Object { $_.Trim() } | Where-Object { $_ })
        if ($Case -eq 'lower') { @($Items | ForEach-Object { $_.ToLower() } | Sort-Object) }
        elseif ($Case -eq 'upper') { @($Items | ForEach-Object { $_.ToUpper() } | Sort-Object) }
        else { @($Items | Sort-Object) }
    }

    $AllowedSenderDomains = & $SplitList $V.AllowedSenderDomains 'none'
    $CurrentAllowed = @(@($Policy.AllowedSenderDomains) | Where-Object { $_ } | Sort-Object)

    $Expected = [PSCustomObject]@{
        name                                 = $PolicyName
        spamAction                           = "$($V.SpamAction)"
        spamQuarantineTag                    = "$($V.SpamQuarantineTag)"
        highConfidenceSpamAction             = "$($V.HighConfidenceSpamAction)"
        highConfidenceSpamQuarantineTag      = "$($V.HighConfidenceSpamQuarantineTag)"
        bulkSpamAction                       = "$($V.BulkSpamAction)"
        bulkQuarantineTag                    = "$($V.BulkQuarantineTag)"
        phishSpamAction                      = "$($V.PhishSpamAction)"
        phishQuarantineTag                   = "$($V.PhishQuarantineTag)"
        highConfidencePhishAction            = 'Quarantine'
        highConfidencePhishQuarantineTag     = "$($V.HighConfidencePhishQuarantineTag)"
        bulkThreshold                        = [int]"$($V.BulkThreshold)"
        quarantineRetentionPeriod            = 30
        increaseScoreWithImageLinks          = (& $OnOff $V.IncreaseScoreWithImageLinks)
        increaseScoreWithNumericIps          = 'Off'
        increaseScoreWithRedirectToOtherPort = 'Off'
        increaseScoreWithBizOrInfoUrls       = (& $OnOff $V.IncreaseScoreWithBizOrInfoUrls)
        markAsSpamEmptyMessages              = 'Off'
        markAsSpamJavaScriptInHtml           = 'Off'
        markAsSpamFramesInHtml               = (& $OnOff $V.MarkAsSpamFramesInHtml)
        markAsSpamObjectTagsInHtml           = (& $OnOff $V.MarkAsSpamObjectTagsInHtml)
        markAsSpamEmbedTagsInHtml            = (& $OnOff $V.MarkAsSpamEmbedTagsInHtml)
        markAsSpamFormTagsInHtml             = (& $OnOff $V.MarkAsSpamFormTagsInHtml)
        markAsSpamWebBugsInHtml              = (& $OnOff $V.MarkAsSpamWebBugsInHtml)
        markAsSpamSensitiveWordList          = (& $OnOff $V.MarkAsSpamSensitiveWordList)
        markAsSpamSpfRecordHardFail          = 'Off'
        markAsSpamFromAddressAuthFail        = 'Off'
        markAsSpamNdrBackscatter             = 'Off'
        markAsSpamBulkMail                   = 'On'
        inlineSafetyTipsEnabled              = $true
        phishZapEnabled                      = $true
        spamZapEnabled                       = $true
        enableLanguageBlockList              = [bool]($V.EnableLanguageBlockList -eq $true)
        enableRegionBlockList                = [bool]($V.EnableRegionBlockList -eq $true)
        allowedSenderDomains                 = @($AllowedSenderDomains)
    }
    $Current = [PSCustomObject]@{
        name                                 = "$($Policy.Name)"
        spamAction                           = "$($Policy.SpamAction)"
        spamQuarantineTag                    = "$($Policy.SpamQuarantineTag)"
        highConfidenceSpamAction             = "$($Policy.HighConfidenceSpamAction)"
        highConfidenceSpamQuarantineTag      = "$($Policy.HighConfidenceSpamQuarantineTag)"
        bulkSpamAction                       = "$($Policy.BulkSpamAction)"
        bulkQuarantineTag                    = "$($Policy.BulkQuarantineTag)"
        phishSpamAction                      = "$($Policy.PhishSpamAction)"
        phishQuarantineTag                   = "$($Policy.PhishQuarantineTag)"
        highConfidencePhishAction            = "$($Policy.HighConfidencePhishAction)"
        highConfidencePhishQuarantineTag     = "$($Policy.HighConfidencePhishQuarantineTag)"
        bulkThreshold                        = $(if ($null -eq $Policy.BulkThreshold) { -1 } else { [int]$Policy.BulkThreshold })
        quarantineRetentionPeriod            = $(if ($null -eq $Policy.QuarantineRetentionPeriod) { -1 } else { [int]$Policy.QuarantineRetentionPeriod })
        increaseScoreWithImageLinks          = "$($Policy.IncreaseScoreWithImageLinks)"
        increaseScoreWithNumericIps          = "$($Policy.IncreaseScoreWithNumericIps)"
        increaseScoreWithRedirectToOtherPort = "$($Policy.IncreaseScoreWithRedirectToOtherPort)"
        increaseScoreWithBizOrInfoUrls       = "$($Policy.IncreaseScoreWithBizOrInfoUrls)"
        markAsSpamEmptyMessages              = "$($Policy.MarkAsSpamEmptyMessages)"
        markAsSpamJavaScriptInHtml           = "$($Policy.MarkAsSpamJavaScriptInHtml)"
        markAsSpamFramesInHtml               = "$($Policy.MarkAsSpamFramesInHtml)"
        markAsSpamObjectTagsInHtml           = "$($Policy.MarkAsSpamObjectTagsInHtml)"
        markAsSpamEmbedTagsInHtml            = "$($Policy.MarkAsSpamEmbedTagsInHtml)"
        markAsSpamFormTagsInHtml             = "$($Policy.MarkAsSpamFormTagsInHtml)"
        markAsSpamWebBugsInHtml              = "$($Policy.MarkAsSpamWebBugsInHtml)"
        markAsSpamSensitiveWordList          = "$($Policy.MarkAsSpamSensitiveWordList)"
        markAsSpamSpfRecordHardFail          = "$($Policy.MarkAsSpamSpfRecordHardFail)"
        markAsSpamFromAddressAuthFail        = "$($Policy.MarkAsSpamFromAddressAuthFail)"
        markAsSpamNdrBackscatter             = "$($Policy.MarkAsSpamNdrBackscatter)"
        markAsSpamBulkMail                   = "$($Policy.MarkAsSpamBulkMail)"
        inlineSafetyTipsEnabled              = [bool]$Policy.InlineSafetyTipsEnabled
        phishZapEnabled                      = [bool]$Policy.PhishZapEnabled
        spamZapEnabled                       = [bool]$Policy.SpamZapEnabled
        enableLanguageBlockList              = [bool]$Policy.EnableLanguageBlockList
        enableRegionBlockList                = [bool]$Policy.EnableRegionBlockList
        # Both-empty counts as equal, matching the classic's null-and-count expression.
        allowedSenderDomains                 = $(if ($CurrentAllowed.Count -eq 0 -and $AllowedSenderDomains.Count -eq 0) { @($AllowedSenderDomains) } else { @($CurrentAllowed) })
    }

    # The block lists are only graded when their switch is on.
    if ($V.EnableLanguageBlockList -eq $true) {
        $Expected | Add-Member -NotePropertyName 'languageBlockList' -NotePropertyValue (& $SplitList $V.LanguageBlockList 'lower')
        $Current | Add-Member -NotePropertyName 'languageBlockList' -NotePropertyValue @(@($Policy.LanguageBlockList) | Where-Object { $_ } | ForEach-Object { "$_".ToLower() } | Sort-Object)
    }
    if ($V.EnableRegionBlockList -eq $true) {
        $Expected | Add-Member -NotePropertyName 'regionBlockList' -NotePropertyValue (& $SplitList $V.RegionBlockList 'upper')
        $Current | Add-Member -NotePropertyName 'regionBlockList' -NotePropertyValue @(@($Policy.RegionBlockList) | Where-Object { $_ } | ForEach-Object { "$_".ToUpper() } | Sort-Object)
    }

    # BulkMovesEnabled (bulk mail to the Promotions folder) is in Preview and not available in
    # every organization, so it is only graded - and written, via extraPolicyParams below - when
    # explicitly configured On or Off. 'Do not configure' never sends the parameter to a tenant
    # that may reject it.
    $BulkMovesEnabled = "$($V.BulkMovesEnabled.value ?? $V.BulkMovesEnabled)"
    if ($BulkMovesEnabled -in @('On', 'Off')) {
        $Expected | Add-Member -NotePropertyName 'bulkMovesEnabled' -NotePropertyValue $BulkMovesEnabled
        $Current | Add-Member -NotePropertyName 'bulkMovesEnabled' -NotePropertyValue "$($Policy.BulkMovesEnabled)"
    }

    # The built-in Default policy cannot carry a rule.
    if (-not $IsDefaultPolicy) {
        $Expected | Add-Member -NotePropertyName 'rule' -NotePropertyValue ([PSCustomObject]@{
                name = $PolicyName; policy = $PolicyName; state = 'Enabled'; priority = 0; recipientDomainIs = @($AcceptedDomains)
            })
        $Current | Add-Member -NotePropertyName 'rule' -NotePropertyValue ([PSCustomObject]@{
                name              = "$($Rule.Name)"
                policy            = "$($Rule.HostedContentFilterPolicy)"
                state             = "$($Rule.State)"
                priority          = $(if ($null -eq $Rule.Priority) { -1 } else { [int]$Rule.Priority })
                recipientDomainIs = @(@($Rule.RecipientDomainIs) | Where-Object { $_ } | Sort-Object)
            })
    }

    $Current | Add-Member -NotePropertyName 'policyName' -NotePropertyValue $PolicyName
    $Current | Add-Member -NotePropertyName 'ruleName' -NotePropertyValue $PolicyName
    $Current | Add-Member -NotePropertyName 'policyExists' -NotePropertyValue ([bool]$Policy)
    $Current | Add-Member -NotePropertyName 'ruleExists' -NotePropertyValue ([bool]$Rule)
    $Current | Add-Member -NotePropertyName 'ruleLinkedPolicy' -NotePropertyValue "$($Rule.HostedContentFilterPolicy)"
    $Current | Add-Member -NotePropertyName 'acceptedDomains' -NotePropertyValue @($AcceptedDomains)
    $Current | Add-Member -NotePropertyName 'skipRule' -NotePropertyValue $IsDefaultPolicy
    # DERIVED write params the static remediate spec cannot express (On/Off strings from
    # switches). Same derivation as the graded Expected above, so grade and write can
    # never disagree - these were graded but never written, drifting forever.
    $ExtraPolicyParams = [ordered]@{
        IncreaseScoreWithImageLinks    = (& $OnOff $V.IncreaseScoreWithImageLinks)
        IncreaseScoreWithBizOrInfoUrls = (& $OnOff $V.IncreaseScoreWithBizOrInfoUrls)
        MarkAsSpamFramesInHtml         = (& $OnOff $V.MarkAsSpamFramesInHtml)
        MarkAsSpamObjectTagsInHtml     = (& $OnOff $V.MarkAsSpamObjectTagsInHtml)
        MarkAsSpamEmbedTagsInHtml      = (& $OnOff $V.MarkAsSpamEmbedTagsInHtml)
        MarkAsSpamFormTagsInHtml       = (& $OnOff $V.MarkAsSpamFormTagsInHtml)
        MarkAsSpamWebBugsInHtml        = (& $OnOff $V.MarkAsSpamWebBugsInHtml)
        MarkAsSpamSensitiveWordList    = (& $OnOff $V.MarkAsSpamSensitiveWordList)
    }
    # The block-list switches follow the classic exactly: enabled with entries writes the
    # switch AND the list, anything else FORCES the switch off - omitting it left a
    # tenant-side 'on' in place forever while the grade expected 'off' (proven live).
    if ($V.EnableLanguageBlockList -eq $true -and @(& $SplitList $V.LanguageBlockList 'lower').Count -gt 0) {
        $ExtraPolicyParams['EnableLanguageBlockList'] = $true
        $ExtraPolicyParams['LanguageBlockList'] = @(& $SplitList $V.LanguageBlockList 'lower')
    } else {
        $ExtraPolicyParams['EnableLanguageBlockList'] = $false
    }
    if ($V.EnableRegionBlockList -eq $true -and @(& $SplitList $V.RegionBlockList 'upper').Count -gt 0) {
        $ExtraPolicyParams['EnableRegionBlockList'] = $true
        $ExtraPolicyParams['RegionBlockList'] = @(& $SplitList $V.RegionBlockList 'upper')
    } else {
        $ExtraPolicyParams['EnableRegionBlockList'] = $false
    }
    if ($BulkMovesEnabled -in @('On', 'Off')) {
        $ExtraPolicyParams['BulkMovesEnabled'] = $BulkMovesEnabled
    }
    $Current | Add-Member -NotePropertyName 'extraPolicyParams' -NotePropertyValue ([PSCustomObject]$ExtraPolicyParams)

    @{ Expected = $Expected; Current = $Current }
}
