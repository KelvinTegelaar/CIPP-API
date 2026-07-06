function Invoke-CIPPStandardSpamFilterPolicy {
    <#
    .FUNCTIONALITY
        Internal
    .COMPONENT
        (APIName) SpamFilterPolicy
    .SYNOPSIS
        (Label) Default Spam Filter Policy
    .DESCRIPTION
        (Helptext) This standard creates a Spam filter policy aligned with the Microsoft Strict preset.
        (DocsDescription) This standard creates a Spam filter policy aligned with the Microsoft Strict preset. All Advanced Spam Filter (ASF) settings are left Off per Microsoft guidance (ASF is deprecated and prevents false-positive reporting). The following settings are configured On by default: MarkAsSpamBulkMail, InlineSafetyTipsEnabled, PhishZapEnabled, SpamZapEnabled.
    .NOTES
        CAT
            Defender Standards
        TAG
            "ORCA100"
            "ORCA101"
            "ORCA102"
            "ORCA103"
            "ORCA104"
            "ORCA123"
            "ORCA139"
            "ORCA140"
            "ORCA141"
            "ORCA142"
            "ORCA143"
            "ORCA224"
            "ORCA231"
            "ORCA241"
            "CISAMSEXO141"
            "CISAMSEXO142"
            "CISAMSEXO143"
        ADDEDCOMPONENT
            {"type":"textField","name":"standards.SpamFilterPolicy.name","label":"Policy Name","required":true,"defaultValue":"CIPP Default Spam Filter Policy"}
            {"type":"number","label":"Bulk email threshold (Default 7)","name":"standards.SpamFilterPolicy.BulkThreshold","defaultValue":7,"validators":{"min":{"value":1,"message":"Minimum value is 1"},"max":{"value":9,"message":"Maximum value is 9"}}}
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
            {"type":"LanguageCodeMultiSelect","required":false,"name":"standards.SpamFilterPolicy.LanguageBlockList","label":"Languages to block (ISO 639-1 two-letter)","condition":{"field":"standards.SpamFilterPolicy.EnableLanguageBlockList","compareType":"is","compareValue":true}}
            {"type":"switch","name":"standards.SpamFilterPolicy.EnableRegionBlockList","label":"Enable region block list","defaultValue":false}
            {"type":"CountryCodeMultiSelect","required":false,"name":"standards.SpamFilterPolicy.RegionBlockList","label":"Regions to block (ISO 3166-1 two-letter)","condition":{"field":"standards.SpamFilterPolicy.EnableRegionBlockList","compareType":"is","compareValue":true}}
            {"type":"autoComplete","multiple":true,"creatable":true,"required":false,"name":"standards.SpamFilterPolicy.AllowedSenderDomains","label":"Allowed sender domains"}
        IMPACT
            Medium Impact
        ADDEDDATE
            2024-07-15
        POWERSHELLEQUIVALENT
            New-HostedContentFilterPolicy or Set-HostedContentFilterPolicy
        RECOMMENDEDBY
        REQUIREDCAPABILITIES
            "EXCHANGE_S_STANDARD"
            "EXCHANGE_S_ENTERPRISE"
            "EXCHANGE_S_STANDARD_GOV"
            "EXCHANGE_S_ENTERPRISE_GOV"
            "EXCHANGE_LITE"
        UPDATECOMMENTBLOCK
            Run the Tools\Update-StandardsComments.ps1 script to update this comment block
    .LINK
        https://docs.cipp.app/user-documentation/tenant/standards/alignment/templates/available-standards
    #>

    param($Tenant, $Settings)
    $TestResult = Test-CIPPStandardLicense -StandardName 'SpamFilterPolicy' -TenantFilter $Tenant -Preset Exchange #No Foundation because that does not allow powershell access

    if ($TestResult -eq $false) {
        return $true
    } #we're done.

    # Use custom name if provided, otherwise use default for backward compatibility
    $DefaultPolicyName = 'CIPP Default Spam Filter Policy'
    $PolicyName = if ($Settings.name) { $Settings.name } else { $DefaultPolicyName }

    try {
        $AllSpamFilterPolicies = New-ExoRequest -TenantId $Tenant -cmdlet 'Get-HostedContentFilterPolicy'
    } catch {
        $ErrorMessage = Get-NormalizedError -Message $_.Exception.Message
        Write-LogMessage -API 'Standards' -Tenant $Tenant -Message "Could not get the SpamFilterPolicy state for $Tenant. Error: $ErrorMessage" -Sev Error
        return
    }

    # Only match against legacy/default names when no custom name is provided. When a custom name is
    # set, deploy it as a new policy instead of reusing an existing default-named one. 'Default' is
    # Microsoft's built-in inbound anti-spam policy ("Anti-spam inbound policy" in the portal); it
    # cannot be renamed and has no associated rule.
    if ($PolicyName -eq $DefaultPolicyName) {
        $PolicyList = @($PolicyName, 'Default Spam Filter Policy', 'Default')
        $ExistingPolicy = $AllSpamFilterPolicies | Where-Object -Property Name -In $PolicyList | Select-Object -First 1
        if ($null -ne $ExistingPolicy.Name) {
            # Use existing policy name if found
            $PolicyName = $ExistingPolicy.Name
        }
    }

    # The built-in default policy cannot have a HostedContentFilterRule, so rule remediation is skipped for it.
    $IsDefaultPolicy = $PolicyName -eq 'Default'

    $CurrentState = $AllSpamFilterPolicies | Where-Object -Property Name -EQ $PolicyName

    $SpamAction = $Settings.SpamAction.value ?? $Settings.SpamAction
    $SpamQuarantineTag = $Settings.SpamQuarantineTag.value ?? $Settings.SpamQuarantineTag
    $HighConfidenceSpamAction = $Settings.HighConfidenceSpamAction.value ?? $Settings.HighConfidenceSpamAction
    $HighConfidenceSpamQuarantineTag = $Settings.HighConfidenceSpamQuarantineTag.value ?? $Settings.HighConfidenceSpamQuarantineTag
    $BulkSpamAction = $Settings.BulkSpamAction.value ?? $Settings.BulkSpamAction
    $BulkQuarantineTag = $Settings.BulkQuarantineTag.value ?? $Settings.BulkQuarantineTag
    $PhishSpamAction = $Settings.PhishSpamAction.value ?? $Settings.PhishSpamAction
    $PhishQuarantineTag = $Settings.PhishQuarantineTag.value ?? $Settings.PhishQuarantineTag
    $HighConfidencePhishQuarantineTag = $Settings.HighConfidencePhishQuarantineTag.value ?? $Settings.HighConfidencePhishQuarantineTag

    # Normalize list settings to clean string arrays. Values may arrive as a proper array or as a
    # single comma-delimited string; splitting and trimming makes Compare-Object and remediation reliable.
    # Case is folded to match what EXO stores and validates: ISO 3166-1 regions uppercase, ISO 639-1 languages lowercase.
    $LanguageBlockList = @(@($Settings.LanguageBlockList.value) | ForEach-Object { $_ -split ',' } | ForEach-Object { $_.Trim().ToLower() } | Where-Object { $_ })
    $RegionBlockList = @(@($Settings.RegionBlockList.value) | ForEach-Object { $_ -split ',' } | ForEach-Object { $_.Trim().ToUpper() } | Where-Object { $_ })
    $AllowedSenderDomains = @(@($Settings.AllowedSenderDomains.value ?? $Settings.AllowedSenderDomains) | ForEach-Object { $_ -split ',' } | ForEach-Object { $_.Trim() } | Where-Object { $_ })

    # Block lists only matter when their Enable* toggle is on; when off, the list is ignored entirely.
    $CurrentLanguageBlockList = @($CurrentState.LanguageBlockList)
    $CurrentRegionBlockList = @($CurrentState.RegionBlockList)
    $LanguageBlockListCorrect = ($Settings.EnableLanguageBlockList -ne $true) -or
        (($CurrentLanguageBlockList.Count -eq $LanguageBlockList.Count) -and (($LanguageBlockList.Count -eq 0) -or !(Compare-Object -ReferenceObject $CurrentLanguageBlockList -DifferenceObject $LanguageBlockList)))
    $RegionBlockListCorrect = ($Settings.EnableRegionBlockList -ne $true) -or
        (($CurrentRegionBlockList.Count -eq $RegionBlockList.Count) -and (($RegionBlockList.Count -eq 0) -or !(Compare-Object -ReferenceObject $CurrentRegionBlockList -DifferenceObject $RegionBlockList)))

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
        ($CurrentState.IncreaseScoreWithNumericIps -eq 'Off') -and
        ($CurrentState.IncreaseScoreWithRedirectToOtherPort -eq 'Off') -and
        ($CurrentState.IncreaseScoreWithBizOrInfoUrls -eq $IncreaseScoreWithBizOrInfoUrls) -and
        ($CurrentState.MarkAsSpamEmptyMessages -eq 'Off') -and
        ($CurrentState.MarkAsSpamJavaScriptInHtml -eq 'Off') -and
        ($CurrentState.MarkAsSpamFramesInHtml -eq $MarkAsSpamFramesInHtml) -and
        ($CurrentState.MarkAsSpamObjectTagsInHtml -eq $MarkAsSpamObjectTagsInHtml) -and
        ($CurrentState.MarkAsSpamEmbedTagsInHtml -eq $MarkAsSpamEmbedTagsInHtml) -and
        ($CurrentState.MarkAsSpamFormTagsInHtml -eq $MarkAsSpamFormTagsInHtml) -and
        ($CurrentState.MarkAsSpamWebBugsInHtml -eq $MarkAsSpamWebBugsInHtml) -and
        ($CurrentState.MarkAsSpamSensitiveWordList -eq $MarkAsSpamSensitiveWordList) -and
        ($CurrentState.MarkAsSpamSpfRecordHardFail -eq 'Off') -and
        ($CurrentState.MarkAsSpamFromAddressAuthFail -eq 'Off') -and
        ($CurrentState.MarkAsSpamNdrBackscatter -eq 'Off') -and
        ($CurrentState.MarkAsSpamBulkMail -eq 'On') -and
        ($CurrentState.InlineSafetyTipsEnabled -eq $true) -and
        ($CurrentState.PhishZapEnabled -eq $true) -and
        ($CurrentState.SpamZapEnabled -eq $true) -and
        ($CurrentState.EnableLanguageBlockList -eq $Settings.EnableLanguageBlockList) -and
        $LanguageBlockListCorrect -and
        ($CurrentState.EnableRegionBlockList -eq $Settings.EnableRegionBlockList) -and
        $RegionBlockListCorrect -and
        ((($null -eq $CurrentState.AllowedSenderDomains -or $CurrentState.AllowedSenderDomains.Count -eq 0) -and ($AllowedSenderDomains.Count -eq 0)) -or ($null -ne $CurrentState.AllowedSenderDomains -and $CurrentState.AllowedSenderDomains.Count -gt 0 -and $AllowedSenderDomains.Count -gt 0 -and !(Compare-Object -ReferenceObject $CurrentState.AllowedSenderDomains -DifferenceObject $AllowedSenderDomains)))
    } catch {
        $StateIsCorrect = $false
    }

    $AcceptedDomains = New-ExoRequest -TenantId $Tenant -cmdlet 'Get-AcceptedDomain'

    $RuleState = New-ExoRequest -TenantId $Tenant -cmdlet 'Get-HostedContentFilterRule' |
    Where-Object -Property Name -EQ $PolicyName

    $RuleStateIsCorrect = ($RuleState.Name -eq $PolicyName) -and
    ($RuleState.HostedContentFilterPolicy -eq $PolicyName) -and
    ($RuleState.State -eq 'Enabled') -and
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
                IncreaseScoreWithNumericIps          = 'Off'
                IncreaseScoreWithRedirectToOtherPort = 'Off'
                IncreaseScoreWithBizOrInfoUrls       = $IncreaseScoreWithBizOrInfoUrls
                MarkAsSpamEmptyMessages              = 'Off'
                MarkAsSpamJavaScriptInHtml           = 'Off'
                MarkAsSpamFramesInHtml               = $MarkAsSpamFramesInHtml
                MarkAsSpamObjectTagsInHtml           = $MarkAsSpamObjectTagsInHtml
                MarkAsSpamEmbedTagsInHtml            = $MarkAsSpamEmbedTagsInHtml
                MarkAsSpamFormTagsInHtml             = $MarkAsSpamFormTagsInHtml
                MarkAsSpamWebBugsInHtml              = $MarkAsSpamWebBugsInHtml
                MarkAsSpamSensitiveWordList          = $MarkAsSpamSensitiveWordList
                MarkAsSpamSpfRecordHardFail          = 'Off'
                MarkAsSpamFromAddressAuthFail        = 'Off'
                MarkAsSpamNdrBackscatter             = 'Off'
                MarkAsSpamBulkMail                   = 'On'
                InlineSafetyTipsEnabled              = $true
                PhishZapEnabled                      = $true
                SpamZapEnabled                       = $true
                AllowedSenderDomains                 = $AllowedSenderDomains.Count -gt 0 ? $AllowedSenderDomains : @{'@odata.type' = '#Exchange.GenericHashTable' }
            }

            # Remove optional block lists if not configured
            if ($Settings.EnableLanguageBlockList -eq $true -and $LanguageBlockList.Count -gt 0) {
                $cmdParams.Add('EnableLanguageBlockList', $Settings.EnableLanguageBlockList)
                $cmdParams.Add('LanguageBlockList', $LanguageBlockList)
            } else {
                $cmdParams.Add('EnableLanguageBlockList', $false)
            }
            if ($Settings.EnableRegionBlockList -eq $true -and $RegionBlockList.Count -gt 0) {
                $cmdParams.Add('EnableRegionBlockList', $Settings.EnableRegionBlockList)
                $cmdParams.Add('RegionBlockList', $RegionBlockList)
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

        if ($RuleStateIsCorrect -eq $false -and -not $IsDefaultPolicy) {
            $cmdParams = @{
                Priority          = 0
                RecipientDomainIs = ConvertTo-SafeArray -Field $AcceptedDomains.Name
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

                if ($RuleState.State -eq 'Disabled') {
                    try {
                        $null = New-ExoRequest -TenantId $Tenant -cmdlet 'Enable-HostedContentFilterRule' -cmdParams @{ Identity = $PolicyName } -UseSystemMailbox $true
                        Write-LogMessage -API 'Standards' -Tenant $Tenant -message "Enabled Spam Filter rule $PolicyName." -sev Info
                    } catch {
                        Write-LogMessage -API 'Standards' -Tenant $Tenant -message "Failed to enable Spam Filter rule $PolicyName." -sev Error -LogData $_
                    }
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
            EnableRegionBlockList            = $CurrentState.EnableRegionBlockList
            AllowedSenderDomains             = $CurrentState.AllowedSenderDomains
        }
        $ExpectedValue = @{
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
            EnableRegionBlockList            = $Settings.EnableRegionBlockList
            AllowedSenderDomains             = $AllowedSenderDomains
        }

        # Only include the block lists in the comparison when their toggle is enabled; otherwise they are ignored.
        if ($Settings.EnableLanguageBlockList) {
            $CurrentValue['LanguageBlockList'] = $CurrentState.LanguageBlockList
            $ExpectedValue['LanguageBlockList'] = $LanguageBlockList
        }
        if ($Settings.EnableRegionBlockList) {
            $CurrentValue['RegionBlockList'] = $CurrentState.RegionBlockList
            $ExpectedValue['RegionBlockList'] = $RegionBlockList
        }

        Set-CIPPStandardsCompareField -FieldName 'standards.SpamFilterPolicy' -CurrentValue $CurrentValue -ExpectedValue $ExpectedValue -Tenant $Tenant
    }
}
