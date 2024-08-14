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
            "mediumimpact"
        ADDEDCOMPONENT
            {"type":"number","label":"Bulk email threshold (Default 7)","name":"standards.SpamFilterPolicy.BulkThreshold","default":7}
            {"type":"Select","label":"Spam Action","name":"standards.SpamFilterPolicy.SpamAction","values":[{"label":"Quarantine the message","value":"Quarantine"},{"label":"Move message to Junk Email folder","value":"MoveToJmf"}]}
            {"type":"Select","label":"Spam Quarantine Tag","name":"standards.SpamFilterPolicy.SpamQuarantineTag","values":[{"label":"AdminOnlyAccessPolicy","value":"AdminOnlyAccessPolicy"},{"label":"DefaultFullAccessPolicy","value":"DefaultFullAccessPolicy"},{"label":"DefaultFullAccessWithNotificationPolicy","value":"DefaultFullAccessWithNotificationPolicy"}]}
            {"type":"Select","label":"High Confidence Spam Action","name":"standards.SpamFilterPolicy.HighConfidenceSpamAction","values":[{"label":"Quarantine the message","value":"Quarantine"},{"label":"Move message to Junk Email folder","value":"MoveToJmf"}]}
            {"type":"Select","label":"High Confidence Spam Quarantine Tag","name":"standards.SpamFilterPolicy.HighConfidenceSpamQuarantineTag","values":[{"label":"AdminOnlyAccessPolicy","value":"AdminOnlyAccessPolicy"},{"label":"DefaultFullAccessPolicy","value":"DefaultFullAccessPolicy"},{"label":"DefaultFullAccessWithNotificationPolicy","value":"DefaultFullAccessWithNotificationPolicy"}]}
            {"type":"Select","label":"Bulk Spam Action","name":"standards.SpamFilterPolicy.BulkSpamAction","values":[{"label":"Quarantine the message","value":"Quarantine"},{"label":"Move message to Junk Email folder","value":"MoveToJmf"}]}
            {"type":"Select","label":"Bulk Quarantine Tag","name":"standards.SpamFilterPolicy.BulkQuarantineTag","values":[{"label":"AdminOnlyAccessPolicy","value":"AdminOnlyAccessPolicy"},{"label":"DefaultFullAccessPolicy","value":"DefaultFullAccessPolicy"},{"label":"DefaultFullAccessWithNotificationPolicy","value":"DefaultFullAccessWithNotificationPolicy"}]}
            {"type":"Select","label":"Phish Spam Action","name":"standards.SpamFilterPolicy.PhishSpamAction","values":[{"label":"Quarantine the message","value":"Quarantine"},{"label":"Move message to Junk Email folder","value":"MoveToJmf"}]}
            {"type":"Select","label":"Phish Quarantine Tag","name":"standards.SpamFilterPolicy.PhishQuarantineTag","values":[{"label":"AdminOnlyAccessPolicy","value":"AdminOnlyAccessPolicy"},{"label":"DefaultFullAccessPolicy","value":"DefaultFullAccessPolicy"},{"label":"DefaultFullAccessWithNotificationPolicy","value":"DefaultFullAccessWithNotificationPolicy"}]}
            {"type":"Select","label":"High Confidence Phish Quarantine Tag","name":"standards.SpamFilterPolicy.HighConfidencePhishQuarantineTag","values":[{"label":"AdminOnlyAccessPolicy","value":"AdminOnlyAccessPolicy"},{"label":"DefaultFullAccessPolicy","value":"DefaultFullAccessPolicy"},{"label":"DefaultFullAccessWithNotificationPolicy","value":"DefaultFullAccessWithNotificationPolicy"}]}
        IMPACT
            Medium Impact
        POWERSHELLEQUIVALENT
            New-HostedContentFilterPolicy or Set-HostedContentFilterPolicy
        RECOMMENDEDBY
        UPDATECOMMENTBLOCK
            Run the Tools\Update-StandardsComments.ps1 script to update this comment block
    .LINK
        https://docs.cipp.app/user-documentation/tenant/standards/edit-standards
    #>

    param($Tenant, $Settings)
    ##$Rerun -Type Standard -Tenant $Tenant -Settings $Settings 'SpamFilterPolicy'

    $PolicyName = 'CIPP Default Spam Filter Policy'

    $CurrentState = New-ExoRequest -TenantId $Tenant -cmdlet 'Get-HostedContentFilterPolicy' |
    Where-Object -Property Name -EQ $PolicyName |
    Select-Object -Property *

    $StateIsCorrect = ($CurrentState.Name -eq $PolicyName) -and
                        ($CurrentState.SpamAction -eq $Settings.SpamAction) -and
                        ($CurrentState.SpamQuarantineTag -eq $Settings.SpamQuarantineTag) -and
                        ($CurrentState.HighConfidenceSpamAction -eq $Settings.HighConfidenceSpamAction) -and
                        ($CurrentState.HighConfidenceSpamQuarantineTag -eq $Settings.HighConfidenceSpamQuarantineTag) -and
                        ($CurrentState.BulkSpamAction -eq $Settings.BulkSpamAction) -and
                        ($CurrentState.BulkQuarantineTag -eq $Settings.BulkQuarantineTag) -and
                        ($CurrentState.PhishSpamAction -eq $Settings.PhishSpamAction) -and
                        ($CurrentState.PhishQuarantineTag -eq $Settings.PhishQuarantineTag) -and
                        ($CurrentState.HighConfidencePhishAction -eq 'Quarantine') -and
                        ($CurrentState.HighConfidencePhishQuarantineTag -eq $Settings.HighConfidencePhishQuarantineTag) -and
                        ($CurrentState.BulkThreshold -eq $Settings.BulkThreshold) -and
                        ($CurrentState.QuarantineRetentionPeriod -eq 30) -and
                        ($CurrentState.IncreaseScoreWithNumericIps -eq 'On') -and
                        ($CurrentState.IncreaseScoreWithRedirectToOtherPort -eq 'On') -and
                        ($CurrentState.MarkAsSpamEmptyMessages -eq 'On') -and
                        ($CurrentState.MarkAsSpamJavaScriptInHtml -eq 'On') -and
                        ($CurrentState.MarkAsSpamSpfRecordHardFail -eq 'On') -and
                        ($CurrentState.MarkAsSpamFromAddressAuthFail -eq 'On') -and
                        ($CurrentState.MarkAsSpamNdrBackscatter -eq 'On') -and
                        ($CurrentState.MarkAsSpamBulkMail -eq 'On') -and
                        ($CurrentState.InlineSafetyTipsEnabled -eq $true) -and
                        ($CurrentState.PhishZapEnabled -eq $true) -and
                        ($CurrentState.SpamZapEnabled -eq $true)

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
                SpamAction                           = $Settings.SpamAction
                SpamQuarantineTag                    = $Settings.SpamQuarantineTag
                HighConfidenceSpamAction             = $Settings.HighConfidenceSpamAction
                HighConfidenceSpamQuarantineTag      = $Settings.HighConfidenceSpamQuarantineTag
                BulkSpamAction                       = $Settings.BulkSpamAction
                BulkQuarantineTag                    = $Settings.BulkQuarantineTag
                PhishSpamAction                      = $Settings.PhishSpamAction
                PhishQuarantineTag                   = $Settings.PhishQuarantineTag
                HighConfidencePhishAction            = 'Quarantine'
                HighConfidencePhishQuarantineTag     = $Settings.HighConfidencePhishQuarantineTag
                BulkThreshold                        = $Settings.BulkThreshold
                QuarantineRetentionPeriod            = 30
                IncreaseScoreWithNumericIps          = 'On'
                IncreaseScoreWithRedirectToOtherPort = 'On'
                MarkAsSpamEmptyMessages              = 'On'
                MarkAsSpamJavaScriptInHtml           = 'On'
                MarkAsSpamSpfRecordHardFail          = 'On'
                MarkAsSpamFromAddressAuthFail        = 'On'
                MarkAsSpamNdrBackscatter             = 'On'
                MarkAsSpamBulkMail                   = 'On'
                InlineSafetyTipsEnabled              = $true
                PhishZapEnabled                      = $true
                SpamZapEnabled                       = $true
            }

            if ($CurrentState.Name -eq $PolicyName) {
                try {
                    $cmdparams.Add('Identity', $PolicyName)
                    New-ExoRequest -TenantId $Tenant -cmdlet 'Set-HostedContentFilterPolicy' -cmdparams $cmdparams -UseSystemMailbox $true
                    Write-LogMessage -API 'Standards' -Tenant $Tenant -message 'Updated Spam Filter Policy' -sev Info
                } catch {
                    $ErrorMessage = Get-NormalizedError -Message $_.Exception.Message
                    Write-LogMessage -API 'Standards' -Tenant $Tenant -message "Failed to update Spam Filter Policy. Error: $ErrorMessage" -sev Error
                }
            } else {
                try {
                    $cmdparams.Add('Name', $PolicyName)
                    New-ExoRequest -TenantId $Tenant -cmdlet 'New-HostedContentFilterPolicy' -cmdparams $cmdparams -UseSystemMailbox $true
                    Write-LogMessage -API 'Standards' -Tenant $Tenant -message 'Created Spam Filter Policy' -sev Info
                } catch {
                    $ErrorMessage = Get-NormalizedError -Message $_.Exception.Message
                    Write-LogMessage -API 'Standards' -Tenant $Tenant -message "Failed to create Spam Filter Policy. Error: $ErrorMessage" -sev Error
                }
            }
        }

        if ($RuleStateIsCorrect -eq $false) {
            $cmdparams = @{
                HostedContentFilterPolicy = $PolicyName
                Priority                  = 0
                RecipientDomainIs         = $AcceptedDomains.Name
            }

            if ($RuleState.Name -eq $PolicyName) {
                try {
                    $cmdparams.Add('Identity', "$PolicyName")
                    New-ExoRequest -TenantId $Tenant -cmdlet 'Set-HostedContentFilterRule' -cmdparams $cmdparams -UseSystemMailbox $true
                    Write-LogMessage -API 'Standards' -Tenant $Tenant -message 'Updated Spam Filter Rule' -sev Info
                } catch {
                    $ErrorMessage = Get-NormalizedError -Message $_.Exception.Message
                    Write-LogMessage -API 'Standards' -Tenant $Tenant -message "Failed to update Spam Filter Rule. Error: $ErrorMessage" -sev Error
                }
            } else {
                try {
                    $cmdparams.Add('Name', "$PolicyName")
                    New-ExoRequest -TenantId $Tenant -cmdlet 'New-HostedContentFilterRule' -cmdparams $cmdparams -UseSystemMailbox $true
                    Write-LogMessage -API 'Standards' -Tenant $Tenant -message 'Created Spam Filter Rule' -sev Info
                } catch {
                    $ErrorMessage = Get-NormalizedError -Message $_.Exception.Message
                    Write-LogMessage -API 'Standards' -Tenant $Tenant -message "Failed to create Spam Filter Rule. Error: $ErrorMessage" -sev Error
                }
            }
        }
    }

    if ($Settings.alert -eq $true) {

        if ($StateIsCorrect -eq $true) {
            Write-LogMessage -API 'Standards' -Tenant $Tenant -message 'Spam Filter Policy is enabled' -sev Info
        } else {
            Write-LogMessage -API 'Standards' -Tenant $Tenant -message 'Spam Filter Policy is not enabled' -sev Alert
        }
    }

    if ($Settings.report -eq $true) {
        Add-CIPPBPAField -FieldName 'SpamFilterPolicy' -FieldValue $StateIsCorrect -StoreAs bool -Tenant $tenant
    }

}
