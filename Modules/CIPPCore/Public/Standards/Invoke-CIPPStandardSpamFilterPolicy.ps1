function Invoke-CIPPStandardSpamFilterPolicy {
    <#
    .FUNCTIONALITY
        Internal
    .COMPONENT
        (APIName) SpamFilterPolicy
    .SYNOPSIS
        (Label) Default Spam Filter Policy
    .DESCRIPTION
        (Helptext) This standard creates a Spam filter policy similar to the default strict policy.
        (DocsDescription) This standard creates a Spam filter policy similar to the default strict policy, the following settings are configured to on by default: IncreaseScoreWithNumericIps, IncreaseScoreWithRedirectToOtherPort, MarkAsSpamEmptyMessages, MarkAsSpamJavaScriptInHtml, MarkAsSpamSpfRecordHardFail, MarkAsSpamFromAddressAuthFail, MarkAsSpamNdrBackscatter, MarkAsSpamBulkMail, InlineSafetyTipsEnabled, PhishZapEnabled, SpamZapEnabled
    .NOTES
        CAT
            Defender Standards
        TAG
        ADDEDCOMPONENT
            {"type":"textField","name":"standards.SpamFilterPolicy.name","label":"Policy Name","required":true,"defaultValue":"CIPP Default Spam Filter Policy"}
            {"type":"number","label":"Bulk email threshold (Default 7)","name":"standards.SpamFilterPolicy.BulkThreshold","defaultValue":7}
            {"type":"autoComplete","required":true,"multiple":false,"creatable":false,"label":"Spam Action","name":"standards.SpamFilterPolicy.SpamAction","options":[{"label":"Quarantine the message","value":"Quarantine"},{"label":"Move message to Junk Email folder","value":"MoveToJmf"}]}
            {"type":"autoComplete","required":true,"multiple":false,"creatable":true,"label":"Spam Quarantine Tag","name":"standards.SpamFilterPolicy.SpamQuarantineTag","options":[{"label":"AdminOnlyAccessPolicy","value":"AdminOnlyAccessPolicy"},{"label":"DefaultFullAccessPolicy","value":"DefaultFullAccessPolicy"},{"label":"DefaultFullAccessWithNotificationPolicy","value":"DefaultFullAccessWithNotificationPolicy"}]}
            {"type":"autoComplete","required":true,"multiple":false,"creatable":false,"label":"High Confidence Spam Action","name":"standards.SpamFilterPolicy.HighConfidenceSpamAction","options":[{"label":"Quarantine the message","value":"Quarantine"},{"label":"Move message to Junk Email folder","value":"MoveToJmf"}]}
            {"type":"autoComplete","required":true,"multiple":false,"creatable":true,"label":"High Confidence Spam Quarantine Tag","name":"standards.SpamFilterPolicy.HighConfidenceSpamQuarantineTag","options":[{"label":"AdminOnlyAccessPolicy","value":"AdminOnlyAccessPolicy"},{"label":"DefaultFullAccessPolicy","value":"DefaultFullAccessPolicy"},{"label":"DefaultFullAccessWithNotificationPolicy","value":"DefaultFullAccessWithNotificationPolicy"}]}
            {"type":"autoComplete","required":true,"multiple":false,"creatable":false,"label":"Bulk Spam Action","name":"standards.SpamFilterPolicy.BulkSpamAction","options":[{"label":"Quarantine the message","value":"Quarantine"},{"label":"Move message to Junk Email folder","value":"MoveToJmf"}]}
            {"type":"autoComplete","required":true,"multiple":false,"creatable":true,"label":"Bulk Quarantine Tag","name":"standards.SpamFilterPolicy.BulkQuarantineTag","options":[{"label":"AdminOnlyAccessPolicy","value":"AdminOnlyAccessPolicy"},{"label":"DefaultFullAccessPolicy","value":"DefaultFullAccessPolicy"},{"label":"DefaultFullAccessWithNotificationPolicy","value":"DefaultFullAccessWithNotificationPolicy"}]}
            {"type":"autoComplete","required":true,"multiple":false,"creatable":false,"label":"Phish Spam Action","name":"standards.SpamFilterPolicy.PhishSpamAction","options":[{"label":"Quarantine the message","value":"Quarantine"},{"label":"Move message to Junk Email folder","value":"MoveToJmf"}]}
            {"type":"autoComplete","required":true,"multiple":false,"creatable":true,"label":"Phish Quarantine Tag","name":"standards.SpamFilterPolicy.PhishQuarantineTag","options":[{"label":"AdminOnlyAccessPolicy","value":"AdminOnlyAccessPolicy"},{"label":"DefaultFullAccessPolicy","value":"DefaultFullAccessPolicy"},{"label":"DefaultFullAccessWithNotificationPolicy","value":"DefaultFullAccessWithNotificationPolicy"}]}
            {"type":"autoComplete","required":true,"multiple":false,"creatable":true,"label":"High Confidence Phish Quarantine Tag","name":"standards.SpamFilterPolicy.HighConfidencePhishQuarantineTag","options":[{"label":"AdminOnlyAccessPolicy","value":"AdminOnlyAccessPolicy"},{"label":"DefaultFullAccessPolicy","value":"DefaultFullAccessPolicy"},{"label":"DefaultFullAccessWithNotificationPolicy","value":"DefaultFullAccessWithNotificationPolicy"}]}
            {"type":"switch","name":"standards.SpamFilterPolicy.IncreaseScoreWithImageLinks","label":"Increase score if message contains image links to remote websites","defaultValue":false}
            {"type":"switch","name":"standards.SpamFilterPolicy.IncreaseScoreWithBizOrInfoUrls","label":"Increase score if message contains links to .biz or .info domains","defaultValue":false}
            {"type":"switch","name":"standards.SpamFilterPolicy.MarkAsSpamFramesInHtml","label":"Mark as spam if message contains HTML or iframe tags","defaultValue":false}
            {"type":"switch","name":"standards.SpamFilterPolicy.MarkAsSpamObjectTagsInHtml","label":"Mark as spam if message contains HTML object tags","defaultValue":false}
            {"type":"switch","name":"standards.SpamFilterPolicy.MarkAsSpamEmbedTagsInHtml","label":"Mark as spam if message contains HTML embed tags","defaultValue":false}
            {"type":"switch","name":"standards.SpamFilterPolicy.MarkAsSpamFormTagsInHtml","label":"Mark as spam if message contains HTML form tags","defaultValue":false}
            {"type":"switch","name":"standards.SpamFilterPolicy.MarkAsSpamWebBugsInHtml","label":"Mark as spam if message contains web bugs (also known as web beacons)","defaultValue":false}
            {"type":"switch","name":"standards.SpamFilterPolicy.MarkAsSpamSensitiveWordList","label":"Mark as spam if message contains words from the sensitive words list","defaultValue":false}
            {"type":"switch","name":"standards.SpamFilterPolicy.EnableLanguageBlockList","label":"Enable language block list","defaultValue":false}
            {"type":"autoComplete","multiple":true,"creatable":true,"required":false,"name":"standards.SpamFilterPolicy.LanguageBlockList","label":"Languages to block (uppercase ISO 639-1 two-letter)","condition":{"field":"standards.SpamFilterPolicy.EnableLanguageBlockList","compareType":"is","compareValue":true}}
            {"type":"switch","name":"standards.SpamFilterPolicy.EnableRegionBlockList","label":"Enable region block list","defaultValue":false}
            {"type":"autoComplete","multiple":true,"creatable":true,"required":false,"name":"standards.SpamFilterPolicy.RegionBlockList","label":"Regions to block (uppercase ISO 3166-1 two-letter)","condition":{"field":"standards.SpamFilterPolicy.EnableRegionBlockList","compareType":"is","compareValue":true}}
            {"type":"autoComplete","multiple":true,"creatable":true,"required":false,"name":"standards.SpamFilterPolicy.AllowedSenderDomains","label":"Allowed sender domains"}
        IMPACT
            Medium Impact
        ADDEDDATE
            2024-07-15
        POWERSHELLEQUIVALENT
            New-HostedContentFilterPolicy or Set-HostedContentFilterPolicy
        RECOMMENDEDBY
        UPDATECOMMENTBLOCK
            Run the Tools\Update-StandardsComments.ps1 script to update this comment block
    .LINK
        https://docs.cipp.app/user-documentation/tenant/standards/list-standards
    #>

    param($Tenant, $Settings)
    $TestResult = Test-CIPPStandardLicense -StandardName 'SpamFilterPolicy' -TenantFilter $Tenant -RequiredCapabilities @('EXCHANGE_S_STANDARD', 'EXCHANGE_S_ENTERPRISE', 'EXCHANGE_S_STANDARD_GOV', 'EXCHANGE_S_ENTERPRISE_GOV', 'EXCHANGE_LITE') #No Foundation because that does not allow powershell access

    if ($TestResult -eq $false) {
        return $true
    } #we're done.

    # Use custom name if provided, otherwise use default for backward compatibility
    $PolicyName = if ($Settings.name) { $Settings.name } else { 'CIPP Default Spam Filter Policy' }

    try {
        $CurrentState = New-ExoRequest -TenantId $Tenant -cmdlet 'Get-HostedContentFilterPolicy' |
            Where-Object -Property Name -EQ $PolicyName
    } catch {
        $ErrorMessage = Get-NormalizedError -Message $_.Exception.Message
        Write-LogMessage -API 'Standards' -Tenant $Tenant -Message "Could not get the SpamFilterPolicy state for $Tenant. Error: $ErrorMessage" -Sev Error
        return
    }

    $SpamAction = $Settings.SpamAction.value ?? $Settings.SpamAction
    $SpamQuarantineTag = $Settings.SpamQuarantineTag.value ?? $Settings.SpamQuarantineTag
    $HighConfidenceSpamAction = $Settings.HighConfidenceSpamAction.value ?? $Settings.HighConfidenceSpamAction
    $HighConfidenceSpamQuarantineTag = $Settings.HighConfidenceSpamQuarantineTag.value ?? $Settings.HighConfidenceSpamQuarantineTag
    $BulkSpamAction = $Settings.BulkSpamAction.value ?? $Settings.BulkSpamAction
    $BulkQuarantineTag = $Settings.BulkQuarantineTag.value ?? $Settings.BulkQuarantineTag
    $PhishSpamAction = $Settings.PhishSpamAction.value ?? $Settings.PhishSpamAction
    $PhishQuarantineTag = $Settings.PhishQuarantineTag.value ?? $Settings.PhishQuarantineTag
    $HighConfidencePhishQuarantineTag = $Settings.HighConfidencePhishQuarantineTag.value ?? $Settings.HighConfidencePhishQuarantineTag

    $IncreaseScoreWithImageLinks = if ($Settings.IncreaseScoreWithImageLinks) { 'On' } else { 'Off' }
    $IncreaseScoreWithBizOrInfoUrls = if ($Settings.IncreaseScoreWithBizOrInfoUrls) { 'On' } else { 'Off' }
    $MarkAsSpamFramesInHtml = if ($Settings.MarkAsSpamFramesInHtml) { 'On' } else { 'Off' }
    $MarkAsSpamObjectTagsInHtml = if ($Settings.MarkAsSpamObjectTagsInHtml) { 'On' } else { 'Off' }
    $MarkAsSpamEmbedTagsInHtml = if ($Settings.MarkAsSpamEmbedTagsInHtml) { 'On' } else { 'Off' }
    $MarkAsSpamFormTagsInHtml = if ($Settings.MarkAsSpamFormTagsInHtml) { 'On' } else { 'Off' }
    $MarkAsSpamWebBugsInHtml = if ($Settings.MarkAsSpamWebBugsInHtml) { 'On' } else { 'Off' }
    $MarkAsSpamSensitiveWordList = if ($Settings.MarkAsSpamSensitiveWordList) { 'On' } else { 'Off' }

    try {
        $StateIsCorrect = ($CurrentState.Name -eq $PolicyName) -and
        ($CurrentState.SpamAction -eq $SpamAction) -and
        ($CurrentState.SpamQuarantineTag -eq $SpamQuarantineTag) -and
        ($CurrentState.HighConfidenceSpamAction -eq $HighConfidenceSpamAction) -and
        ($CurrentState.HighConfidenceSpamQuarantineTag -eq $HighConfidenceSpamQuarantineTag) -and
        ($CurrentState.BulkSpamAction -eq $BulkSpamAction) -and
        ($CurrentState.BulkQuarantineTag -eq $BulkQuarantineTag) -and
        ($CurrentState.PhishSpamAction -eq $PhishSpamAction) -and
        ($CurrentState.PhishQuarantineTag -eq $PhishQuarantineTag) -and
        ($CurrentState.HighConfidencePhishAction -eq 'Quarantine') -and
        ($CurrentState.HighConfidencePhishQuarantineTag -eq $HighConfidencePhishQuarantineTag) -and
        ($CurrentState.BulkThreshold -eq [int]$Settings.BulkThreshold) -and
        ($CurrentState.QuarantineRetentionPeriod -eq 30) -and
        ($CurrentState.IncreaseScoreWithImageLinks -eq $IncreaseScoreWithImageLinks) -and
        ($CurrentState.IncreaseScoreWithNumericIps -eq 'On') -and
        ($CurrentState.IncreaseScoreWithRedirectToOtherPort -eq 'On') -and
        ($CurrentState.IncreaseScoreWithBizOrInfoUrls -eq $IncreaseScoreWithBizOrInfoUrls) -and
        ($CurrentState.MarkAsSpamEmptyMessages -eq 'On') -and
        ($CurrentState.MarkAsSpamJavaScriptInHtml -eq 'On') -and
        ($CurrentState.MarkAsSpamFramesInHtml -eq $MarkAsSpamFramesInHtml) -and
        ($CurrentState.MarkAsSpamObjectTagsInHtml -eq $MarkAsSpamObjectTagsInHtml) -and
        ($CurrentState.MarkAsSpamEmbedTagsInHtml -eq $MarkAsSpamEmbedTagsInHtml) -and
        ($CurrentState.MarkAsSpamFormTagsInHtml -eq $MarkAsSpamFormTagsInHtml) -and
        ($CurrentState.MarkAsSpamWebBugsInHtml -eq $MarkAsSpamWebBugsInHtml) -and
        ($CurrentState.MarkAsSpamSensitiveWordList -eq $MarkAsSpamSensitiveWordList) -and
        ($CurrentState.MarkAsSpamSpfRecordHardFail -eq 'On') -and
        ($CurrentState.MarkAsSpamFromAddressAuthFail -eq 'On') -and
        ($CurrentState.MarkAsSpamNdrBackscatter -eq 'On') -and
        ($CurrentState.MarkAsSpamBulkMail -eq 'On') -and
        ($CurrentState.InlineSafetyTipsEnabled -eq $true) -and
        ($CurrentState.PhishZapEnabled -eq $true) -and
        ($CurrentState.SpamZapEnabled -eq $true) -and
        ($CurrentState.EnableLanguageBlockList -eq $Settings.EnableLanguageBlockList) -and
        ((($null -eq $CurrentState.LanguageBlockList -or $CurrentState.LanguageBlockList.Count -eq 0) -and ($null -eq $Settings.LanguageBlockList.value)) -or ($null -ne $CurrentState.LanguageBlockList -and $CurrentState.LanguageBlockList.Count -gt 0 -and $null -ne $Settings.LanguageBlockList.value -and !(Compare-Object -ReferenceObject $CurrentState.LanguageBlockList -DifferenceObject $Settings.LanguageBlockList.value))) -and
        ($CurrentState.EnableRegionBlockList -eq $Settings.EnableRegionBlockList) -and
        ((($null -eq $CurrentState.RegionBlockList -or $CurrentState.RegionBlockList.Count -eq 0) -and ($null -eq $Settings.RegionBlockList.value)) -or ($null -ne $CurrentState.RegionBlockList -and $CurrentState.RegionBlockList.Count -gt 0 -and $null -ne $Settings.RegionBlockList.value -and !(Compare-Object -ReferenceObject $CurrentState.RegionBlockList -DifferenceObject $Settings.RegionBlockList.value))) -and
        ((($null -eq $CurrentState.AllowedSenderDomains -or $CurrentState.AllowedSenderDomains.Count -eq 0) -and ($null -eq ($Settings.AllowedSenderDomains.value ?? $Settings.AllowedSenderDomains))) -or ($null -ne $CurrentState.AllowedSenderDomains -and $CurrentState.AllowedSenderDomains.Count -gt 0 -and $null -ne ($Settings.AllowedSenderDomains.value ?? $Settings.AllowedSenderDomains) -and !(Compare-Object -ReferenceObject $CurrentState.AllowedSenderDomains -DifferenceObject ($Settings.AllowedSenderDomains.value ?? $Settings.AllowedSenderDomains))))
    } catch {
        $StateIsCorrect = $false
    }

    $AcceptedDomains = New-ExoRequest -TenantId $Tenant -cmdlet 'Get-AcceptedDomain'

    $RuleState = New-ExoRequest -TenantId $Tenant -cmdlet 'Get-HostedContentFilterRule' |
        Where-Object -Property Name -EQ $PolicyName

    $RuleStateIsCorrect = ($RuleState.Name -eq $PolicyName) -and
    ($RuleState.HostedContentFilterPolicy -eq $PolicyName) -and
    ($RuleState.Priority -eq 0) -and
    (!(Compare-Object -ReferenceObject $RuleState.RecipientDomainIs -DifferenceObject $AcceptedDomains.Name))

    if ($Settings.remediate -eq $true) {
        if ($StateIsCorrect -eq $true) {
            Write-LogMessage -API 'Standards' -Tenant $Tenant -message 'Spam Filter Policy already correctly configured' -sev Info
        } else {
            $cmdParams = @{
                SpamAction                           = $SpamAction
                SpamQuarantineTag                    = $SpamQuarantineTag
                HighConfidenceSpamAction             = $HighConfidenceSpamAction
                HighConfidenceSpamQuarantineTag      = $HighConfidenceSpamQuarantineTag
                BulkSpamAction                       = $BulkSpamAction
                BulkQuarantineTag                    = $BulkQuarantineTag
                PhishSpamAction                      = $PhishSpamAction
                PhishQuarantineTag                   = $PhishQuarantineTag
                HighConfidencePhishAction            = 'Quarantine'
                HighConfidencePhishQuarantineTag     = $HighConfidencePhishQuarantineTag
                BulkThreshold                        = [int]$Settings.BulkThreshold
                QuarantineRetentionPeriod            = 30
                IncreaseScoreWithImageLinks          = $IncreaseScoreWithImageLinks
                IncreaseScoreWithNumericIps          = 'On'
                IncreaseScoreWithRedirectToOtherPort = 'On'
                IncreaseScoreWithBizOrInfoUrls       = $IncreaseScoreWithBizOrInfoUrls
                MarkAsSpamEmptyMessages              = 'On'
                MarkAsSpamJavaScriptInHtml           = 'On'
                MarkAsSpamFramesInHtml               = $MarkAsSpamFramesInHtml
                MarkAsSpamObjectTagsInHtml           = $MarkAsSpamObjectTagsInHtml
                MarkAsSpamEmbedTagsInHtml            = $MarkAsSpamEmbedTagsInHtml
                MarkAsSpamFormTagsInHtml             = $MarkAsSpamFormTagsInHtml
                MarkAsSpamWebBugsInHtml              = $MarkAsSpamWebBugsInHtml
                MarkAsSpamSensitiveWordList          = $MarkAsSpamSensitiveWordList
                MarkAsSpamSpfRecordHardFail          = 'On'
                MarkAsSpamFromAddressAuthFail        = 'On'
                MarkAsSpamNdrBackscatter             = 'On'
                MarkAsSpamBulkMail                   = 'On'
                InlineSafetyTipsEnabled              = $true
                PhishZapEnabled                      = $true
                SpamZapEnabled                       = $true
                AllowedSenderDomains                 = $Settings.AllowedSenderDomains.value ?? @{'@odata.type' = '#Exchange.GenericHashTable' }
            }

            # Remove optional block lists if not configured
            if ($Settings.EnableLanguageBlockList -eq $true -and $Settings.LanguageBlockList.value) {
                $cmdParams.Add('EnableLanguageBlockList', $Settings.EnableLanguageBlockList)
                $cmdParams.Add('LanguageBlockList', $Settings.LanguageBlockList.value)
            } else {
                $cmdParams.Add('EnableLanguageBlockList', $false)
            }
            if ($Settings.EnableRegionBlockList -eq $true -and $Settings.RegionBlockList.value) {
                $cmdParams.Add('EnableRegionBlockList', $Settings.EnableRegionBlockList)
                $cmdParams.Add('RegionBlockList', $Settings.RegionBlockList.value)
            } else {
                $cmdParams.Add('EnableRegionBlockList', $false)
            }


            if ($CurrentState.Name -eq $PolicyName) {
                try {
                    $cmdParams.Add('Identity', $PolicyName)
                    $null = New-ExoRequest -TenantId $Tenant -cmdlet 'Set-HostedContentFilterPolicy' -cmdParams $cmdParams -UseSystemMailbox $true
                    Write-LogMessage -API 'Standards' -Tenant $Tenant -message "Updated Spam Filter policy $PolicyName." -sev Info
                } catch {
                    Write-LogMessage -API 'Standards' -Tenant $Tenant -message "Failed to update Spam Filter policy $PolicyName." -sev Error -LogData $_
                }
            } else {
                try {
                    $cmdParams.Add('Name', $PolicyName)
                    $null = New-ExoRequest -TenantId $Tenant -cmdlet 'New-HostedContentFilterPolicy' -cmdParams $cmdParams -UseSystemMailbox $true
                    Write-LogMessage -API 'Standards' -Tenant $Tenant -message "Created Spam Filter policy $PolicyName." -sev Info
                } catch {
                    Write-LogMessage -API 'Standards' -Tenant $Tenant -message "Failed to create Spam Filter policy $PolicyName." -sev Error -LogData $_
                }
            }
        }

        if ($RuleStateIsCorrect -eq $false) {
            $cmdParams = @{
                Priority          = 0
                RecipientDomainIs = $AcceptedDomains.Name
            }

            if ($RuleState.HostedContentFilterPolicy -ne $PolicyName) {
                $cmdParams.Add('HostedContentFilterPolicy', $PolicyName)
            }

            if ($RuleState.Name -eq $PolicyName) {
                try {
                    $cmdParams.Add('Identity', "$PolicyName")
                    $null = New-ExoRequest -TenantId $Tenant -cmdlet 'Set-HostedContentFilterRule' -cmdParams $cmdParams -UseSystemMailbox $true
                    Write-LogMessage -API 'Standards' -Tenant $Tenant -message "Updated Spam Filter rule $PolicyName." -sev Info
                } catch {
                    Write-LogMessage -API 'Standards' -Tenant $Tenant -message "Failed to update Spam Filter rule $PolicyName." -sev Error -LogData $_
                }
            } else {
                try {
                    $cmdParams.Add('Name', "$PolicyName")
                    $null = New-ExoRequest -TenantId $Tenant -cmdlet 'New-HostedContentFilterRule' -cmdParams $cmdParams -UseSystemMailbox $true
                    Write-LogMessage -API 'Standards' -Tenant $Tenant -message "Created Spam Filter rule $PolicyName." -sev Info
                } catch {
                    Write-LogMessage -API 'Standards' -Tenant $Tenant -message "Failed to create Spam Filter rule $PolicyName." -sev Error -LogData $_
                }
            }
        }
    }

    if ($Settings.alert -eq $true) {
        if ($StateIsCorrect -eq $true) {
            Write-LogMessage -API 'Standards' -Tenant $Tenant -message 'Spam Filter Policy is enabled' -sev Info
        } else {
            Write-StandardsAlert -message 'Spam Filter Policy is not enabled' -object $CurrentState -tenant $Tenant -standardName 'SpamFilterPolicy' -standardId $Settings.standardId
            Write-LogMessage -API 'Standards' -Tenant $Tenant -message 'Spam Filter Policy is not enabled' -sev Info
        }
    }

    if ($Settings.report -eq $true) {
        Add-CIPPBPAField -FieldName 'SpamFilterPolicy' -FieldValue $StateIsCorrect -StoreAs bool -Tenant $Tenant
        $CurrentValue = @{
            Name                             = $CurrentState.Name
            SpamAction                       = $CurrentState.SpamAction
            SpamQuarantineTag                = $CurrentState.SpamQuarantineTag
            HighConfidenceSpamAction         = $CurrentState.HighConfidenceSpamAction
            HighConfidenceSpamQuarantineTag  = $CurrentState.HighConfidenceSpamQuarantineTag
            BulkSpamAction                   = $CurrentState.BulkSpamAction
            BulkQuarantineTag                = $CurrentState.BulkQuarantineTag
            PhishSpamAction                  = $CurrentState.PhishSpamAction
            PhishQuarantineTag               = $CurrentState.PhishQuarantineTag
            HighConfidencePhishQuarantineTag = $CurrentState.HighConfidencePhishQuarantineTag
            BulkThreshold                    = $CurrentState.BulkThreshold
            IncreaseScoreWithImageLinks      = $CurrentState.IncreaseScoreWithImageLinks
            IncreaseScoreWithBizOrInfoUrls   = $CurrentState.IncreaseScoreWithBizOrInfoUrls
            MarkAsSpamFramesInHtml           = $CurrentState.MarkAsSpamFramesInHtml
            MarkAsSpamObjectTagsInHtml       = $CurrentState.MarkAsSpamObjectTagsInHtml
            MarkAsSpamEmbedTagsInHtml        = $CurrentState.MarkAsSpamEmbedTagsInHtml
            MarkAsSpamFormTagsInHtml         = $CurrentState.MarkAsSpamFormTagsInHtml
            MarkAsSpamWebBugsInHtml          = $CurrentState.MarkAsSpamWebBugsInHtml
            MarkAsSpamSensitiveWordList      = $CurrentState.MarkAsSpamSensitiveWordList
            EnableLanguageBlockList          = $CurrentState.EnableLanguageBlockList
            LanguageBlockList                = $CurrentState.LanguageBlockList
            EnableRegionBlockList            = $CurrentState.EnableRegionBlockList
            RegionBlockList                  = $CurrentState.RegionBlockList
            AllowedSenderDomains             = $CurrentState.AllowedSenderDomains
        }
        $ExpectedValue = [pscustomobject]@{
            Name                             = $PolicyName
            SpamAction                       = $SpamAction
            SpamQuarantineTag                = $SpamQuarantineTag
            HighConfidenceSpamAction         = $HighConfidenceSpamAction
            HighConfidenceSpamQuarantineTag  = $HighConfidenceSpamQuarantineTag
            BulkSpamAction                   = $BulkSpamAction
            BulkQuarantineTag                = $BulkQuarantineTag
            PhishSpamAction                  = $PhishSpamAction
            PhishQuarantineTag               = $PhishQuarantineTag
            HighConfidencePhishQuarantineTag = $HighConfidencePhishQuarantineTag
            BulkThreshold                    = [int]$Settings.BulkThreshold
            IncreaseScoreWithImageLinks      = $IncreaseScoreWithImageLinks
            IncreaseScoreWithBizOrInfoUrls   = $IncreaseScoreWithBizOrInfoUrls
            MarkAsSpamFramesInHtml           = $MarkAsSpamFramesInHtml
            MarkAsSpamObjectTagsInHtml       = $MarkAsSpamObjectTagsInHtml
            MarkAsSpamEmbedTagsInHtml        = $MarkAsSpamEmbedTagsInHtml
            MarkAsSpamFormTagsInHtml         = $MarkAsSpamFormTagsInHtml
            MarkAsSpamWebBugsInHtml          = $MarkAsSpamWebBugsInHtml
            MarkAsSpamSensitiveWordList      = $MarkAsSpamSensitiveWordList
            EnableLanguageBlockList          = $Settings.EnableLanguageBlockList
            LanguageBlockList                = $Settings.EnableLanguageBlockList ? @($Settings.EnableLanguageBlockList) : @()
            EnableRegionBlockList            = $Settings.EnableRegionBlockList
            RegionBlockList                  = $Settings.RegionBlockList.value ? @($Settings.RegionBlockList.value) : @()
            AllowedSenderDomains             = $Settings.AllowedSenderDomains.value ? @($Settings.AllowedSenderDomains.value) : @()
        }
        Set-CIPPStandardsCompareField -FieldName 'standards.SpamFilterPolicy' -CurrentValue $CurrentValue -ExpectedValue $ExpectedValue -Tenant $Tenant
    }
}
