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
        (DocsDescription) This standard creates a Spam filter policy similar to the default strict policy.
    .NOTES
        CAT
            Defender Standards
        TAG
        ADDEDCOMPONENT
            {"type":"number","label":"Bulk email threshold (Default 7)","name":"standards.SpamFilterPolicy.BulkThreshold","defaultValue":7}
            {"type":"autoComplete","required":true,"multiple":false,"creatable":false,"label":"Spam Action","name":"standards.SpamFilterPolicy.SpamAction","options":[{"label":"Quarantine the message","value":"Quarantine"},{"label":"Move message to Junk Email folder","value":"MoveToJmf"}]}
            {"type":"autoComplete","required":true,"multiple":false,"creatable":false,"label":"Spam Quarantine Tag","name":"standards.SpamFilterPolicy.SpamQuarantineTag","options":[{"label":"AdminOnlyAccessPolicy","value":"AdminOnlyAccessPolicy"},{"label":"DefaultFullAccessPolicy","value":"DefaultFullAccessPolicy"},{"label":"DefaultFullAccessWithNotificationPolicy","value":"DefaultFullAccessWithNotificationPolicy"}]}
            {"type":"autoComplete","required":true,"multiple":false,"creatable":false,"label":"High Confidence Spam Action","name":"standards.SpamFilterPolicy.HighConfidenceSpamAction","options":[{"label":"Quarantine the message","value":"Quarantine"},{"label":"Move message to Junk Email folder","value":"MoveToJmf"}]}
            {"type":"autoComplete","required":true,"multiple":false,"creatable":false,"label":"High Confidence Spam Quarantine Tag","name":"standards.SpamFilterPolicy.HighConfidenceSpamQuarantineTag","options":[{"label":"AdminOnlyAccessPolicy","value":"AdminOnlyAccessPolicy"},{"label":"DefaultFullAccessPolicy","value":"DefaultFullAccessPolicy"},{"label":"DefaultFullAccessWithNotificationPolicy","value":"DefaultFullAccessWithNotificationPolicy"}]}
            {"type":"autoComplete","required":true,"multiple":false,"creatable":false,"label":"Bulk Spam Action","name":"standards.SpamFilterPolicy.BulkSpamAction","options":[{"label":"Quarantine the message","value":"Quarantine"},{"label":"Move message to Junk Email folder","value":"MoveToJmf"}]}
            {"type":"autoComplete","required":true,"multiple":false,"creatable":false,"label":"Bulk Quarantine Tag","name":"standards.SpamFilterPolicy.BulkQuarantineTag","options":[{"label":"AdminOnlyAccessPolicy","value":"AdminOnlyAccessPolicy"},{"label":"DefaultFullAccessPolicy","value":"DefaultFullAccessPolicy"},{"label":"DefaultFullAccessWithNotificationPolicy","value":"DefaultFullAccessWithNotificationPolicy"}]}
            {"type":"autoComplete","required":true,"multiple":false,"creatable":false,"label":"Phish Spam Action","name":"standards.SpamFilterPolicy.PhishSpamAction","options":[{"label":"Quarantine the message","value":"Quarantine"},{"label":"Move message to Junk Email folder","value":"MoveToJmf"}]}
            {"type":"autoComplete","required":true,"multiple":false,"creatable":false,"label":"Phish Quarantine Tag","name":"standards.SpamFilterPolicy.PhishQuarantineTag","options":[{"label":"AdminOnlyAccessPolicy","value":"AdminOnlyAccessPolicy"},{"label":"DefaultFullAccessPolicy","value":"DefaultFullAccessPolicy"},{"label":"DefaultFullAccessWithNotificationPolicy","value":"DefaultFullAccessWithNotificationPolicy"}]}
            {"type":"autoComplete","required":true,"multiple":false,"creatable":false,"label":"High Confidence Phish Quarantine Tag","name":"standards.SpamFilterPolicy.HighConfidencePhishQuarantineTag","options":[{"label":"AdminOnlyAccessPolicy","value":"AdminOnlyAccessPolicy"},{"label":"DefaultFullAccessPolicy","value":"DefaultFullAccessPolicy"},{"label":"DefaultFullAccessWithNotificationPolicy","value":"DefaultFullAccessWithNotificationPolicy"}]}
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
        https://docs.cipp.app/user-documentation/tenant/standards/list-standards/defender-standards#medium-impact
    #>

    param($Tenant, $Settings)

    $PolicyName = 'CIPP Default Spam Filter Policy'

    $CurrentState = New-ExoRequest -TenantId $Tenant -cmdlet 'Get-HostedContentFilterPolicy' | Where-Object -Property Name -EQ $PolicyName | Select-Object -Property *

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
    ($CurrentState.BulkThreshold -eq $Settings.BulkThreshold) -and
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
    ((-not $CurrentState.LanguageBlockList -and -not $Settings.LanguageBlockList.value) -or (!(Compare-Object -ReferenceObject $CurrentState.LanguageBlockList -DifferenceObject $Settings.LanguageBlockList.value))) -and
    ($CurrentState.EnableRegionBlockList -eq $Settings.EnableRegionBlockList) -and
    ((-not $CurrentState.RegionBlockList -and -not $Settings.RegionBlockList.value) -or (!(Compare-Object -ReferenceObject $CurrentState.RegionBlockList -DifferenceObject $Settings.RegionBlockList.value))) -and
    (!(Compare-Object -ReferenceObject $CurrentState.AllowedSenderDomains -DifferenceObject ($Settings.AllowedSenderDomains.value ?? $Settings.AllowedSenderDomains)))

    $AcceptedDomains = New-ExoRequest -TenantId $Tenant -cmdlet 'Get-AcceptedDomain'

    $RuleState = New-ExoRequest -TenantId $Tenant -cmdlet 'Get-HostedContentFilterRule' |
    Where-Object -Property Name -EQ $PolicyName |
    Select-Object -Property *

    $RuleStateIsCorrect = ($RuleState.Name -eq $PolicyName) -and
    ($RuleState.HostedContentFilterPolicy -eq $PolicyName) -and
    ($RuleState.Priority -eq 0) -and
    (!(Compare-Object -ReferenceObject $RuleState.RecipientDomainIs -DifferenceObject $AcceptedDomains.Name))

    if ($Settings.remediate -eq $true) {
        if ($StateIsCorrect -eq $true) {
            Write-LogMessage -API 'Standards' -Tenant $Tenant -message 'Spam Filter Policy already correctly configured' -sev Info
        } else {
            $cmdparams = @{
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
                BulkThreshold                        = $Settings.BulkThreshold
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
                EnableLanguageBlockList              = $Settings.EnableLanguageBlockList
                LanguageBlockList                    = $Settings.LanguageBlockList.value
                EnableRegionBlockList                = $Settings.EnableRegionBlockList
                RegionBlockList                      = $Settings.RegionBlockList.value
                AllowedSenderDomains                 = $Settings.AllowedSenderDomains.value ?? @{'@odata.type' = '#Exchange.GenericHashTable' }
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
        if ($StateIsCorrect) {
            $FieldValue = $true
        } else {
            $FieldValue = $CurrentState ? $CurrentState : $false
        }
        Set-CIPPStandardsCompareField -FieldName 'standards.SpamFilterPolicy' -FieldValue $FieldValue -Tenant $Tenant
    }
}
