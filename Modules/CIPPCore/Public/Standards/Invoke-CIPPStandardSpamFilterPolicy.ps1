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
            {"type":"autoComplete","multiple":false,"label":"Spam Action","name":"standards.SpamFilterPolicy.SpamAction","options":[{"label":"Quarantine the message","value":"Quarantine"},{"label":"Move message to Junk Email folder","value":"MoveToJmf"}]}
            {"type":"autoComplete","multiple":false,"label":"Spam Quarantine Tag","name":"standards.SpamFilterPolicy.SpamQuarantineTag","options":[{"label":"AdminOnlyAccessPolicy","value":"AdminOnlyAccessPolicy"},{"label":"DefaultFullAccessPolicy","value":"DefaultFullAccessPolicy"},{"label":"DefaultFullAccessWithNotificationPolicy","value":"DefaultFullAccessWithNotificationPolicy"}]}
            {"type":"autoComplete","multiple":false,"label":"High Confidence Spam Action","name":"standards.SpamFilterPolicy.HighConfidenceSpamAction","options":[{"label":"Quarantine the message","value":"Quarantine"},{"label":"Move message to Junk Email folder","value":"MoveToJmf"}]}
            {"type":"autoComplete","multiple":false,"label":"High Confidence Spam Quarantine Tag","name":"standards.SpamFilterPolicy.HighConfidenceSpamQuarantineTag","options":[{"label":"AdminOnlyAccessPolicy","value":"AdminOnlyAccessPolicy"},{"label":"DefaultFullAccessPolicy","value":"DefaultFullAccessPolicy"},{"label":"DefaultFullAccessWithNotificationPolicy","value":"DefaultFullAccessWithNotificationPolicy"}]}
            {"type":"autoComplete","multiple":false,"label":"Bulk Spam Action","name":"standards.SpamFilterPolicy.BulkSpamAction","options":[{"label":"Quarantine the message","value":"Quarantine"},{"label":"Move message to Junk Email folder","value":"MoveToJmf"}]}
            {"type":"autoComplete","multiple":false,"label":"Bulk Quarantine Tag","name":"standards.SpamFilterPolicy.BulkQuarantineTag","options":[{"label":"AdminOnlyAccessPolicy","value":"AdminOnlyAccessPolicy"},{"label":"DefaultFullAccessPolicy","value":"DefaultFullAccessPolicy"},{"label":"DefaultFullAccessWithNotificationPolicy","value":"DefaultFullAccessWithNotificationPolicy"}]}
            {"type":"autoComplete","multiple":false,"label":"Phish Spam Action","name":"standards.SpamFilterPolicy.PhishSpamAction","options":[{"label":"Quarantine the message","value":"Quarantine"},{"label":"Move message to Junk Email folder","value":"MoveToJmf"}]}
            {"type":"autoComplete","multiple":false,"label":"Phish Quarantine Tag","name":"standards.SpamFilterPolicy.PhishQuarantineTag","options":[{"label":"AdminOnlyAccessPolicy","value":"AdminOnlyAccessPolicy"},{"label":"DefaultFullAccessPolicy","value":"DefaultFullAccessPolicy"},{"label":"DefaultFullAccessWithNotificationPolicy","value":"DefaultFullAccessWithNotificationPolicy"}]}
            {"type":"autoComplete","multiple":false,"label":"High Confidence Phish Quarantine Tag","name":"standards.SpamFilterPolicy.HighConfidencePhishQuarantineTag","options":[{"label":"AdminOnlyAccessPolicy","value":"AdminOnlyAccessPolicy"},{"label":"DefaultFullAccessPolicy","value":"DefaultFullAccessPolicy"},{"label":"DefaultFullAccessWithNotificationPolicy","value":"DefaultFullAccessWithNotificationPolicy"}]}
        IMPACT
            Medium Impact
        POWERSHELLEQUIVALENT
            New-HostedContentFilterPolicy or Set-HostedContentFilterPolicy
        RECOMMENDEDBY
        UPDATECOMMENTBLOCK
            Run the Tools\Update-StandardsComments.ps1 script to update this comment block
    .LINK
        https://docs.cipp.app/user-documentation/tenant/standards/list-standards/defender-standards#medium-impact
    #>

    param($Tenant, $Settings)
    ##$Rerun -Type Standard -Tenant $Tenant -Settings $Settings 'SpamFilterPolicy'

    $PolicyName = 'CIPP Default Spam Filter Policy'

    $CurrentState = New-ExoRequest -TenantId $Tenant -cmdlet 'Get-HostedContentFilterPolicy' |
        Where-Object -Property Name -EQ $PolicyName |
        Select-Object -Property *

    $StateIsCorrect = ($CurrentState.Name -eq $PolicyName) -and
                        ($CurrentState.SpamAction -eq $Settings.SpamAction.value) -and
                        ($CurrentState.SpamQuarantineTag -eq $Settings.SpamQuarantineTag.value) -and
                        ($CurrentState.HighConfidenceSpamAction -eq $Settings.HighConfidenceSpamAction.value) -and
                        ($CurrentState.HighConfidenceSpamQuarantineTag -eq $Settings.HighConfidenceSpamQuarantineTag.value) -and
                        ($CurrentState.BulkSpamAction -eq $Settings.BulkSpamAction.value) -and
                        ($CurrentState.BulkQuarantineTag -eq $Settings.BulkQuarantineTag.value) -and
                        ($CurrentState.PhishSpamAction -eq $Settings.PhishSpamAction.value) -and
                        ($CurrentState.PhishQuarantineTag -eq $Settings.PhishQuarantineTag.value) -and
                        ($CurrentState.HighConfidencePhishAction -eq 'Quarantine') -and
                        ($CurrentState.HighConfidencePhishQuarantineTag -eq $Settings.HighConfidencePhishQuarantineTag.value) -and
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
                SpamAction                           = $Settings.SpamAction.value
                SpamQuarantineTag                    = $Settings.SpamQuarantineTag.value
                HighConfidenceSpamAction             = $Settings.HighConfidenceSpamAction.value
                HighConfidenceSpamQuarantineTag      = $Settings.HighConfidenceSpamQuarantineTag.value
                BulkSpamAction                       = $Settings.BulkSpamAction.value
                BulkQuarantineTag                    = $Settings.BulkQuarantineTag.value
                PhishSpamAction                      = $Settings.PhishSpamAction.value
                PhishQuarantineTag                   = $Settings.PhishQuarantineTag.value
                HighConfidencePhishAction            = 'Quarantine'
                HighConfidencePhishQuarantineTag     = $Settings.HighConfidencePhishQuarantineTag.value
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
            Write-Host "================== DEBUG =================="
            Write-Host $cmdparams

            if ($CurrentState.Name -eq $PolicyName) {
                try {
                    $cmdparams.Add('Identity', $PolicyName)
                    New-ExoRequest -TenantId $Tenant -cmdlet 'Set-HostedContentFilterPolicy' -cmdparams $cmdparams -UseSystemMailbox $true
                    Write-LogMessage -API 'Standards' -Tenant $Tenant -message "Updated Spam Filter policy $PolicyName." -sev Info
                } catch {
                    Write-LogMessage -API 'Standards' -Tenant $Tenant -message "Failed to update Spam Filter policy $PolicyName." -sev Error -LogData $_
                }
            } else {
                try {
                    $cmdparams.Add('Name', $PolicyName)
                    New-ExoRequest -TenantId $Tenant -cmdlet 'New-HostedContentFilterPolicy' -cmdparams $cmdparams -UseSystemMailbox $true
                    Write-LogMessage -API 'Standards' -Tenant $Tenant -message "Created Spam Filter policy $PolicyName." -sev Info
                } catch {
                    Write-LogMessage -API 'Standards' -Tenant $Tenant -message "Failed to create Spam Filter policy $PolicyName." -sev Error -LogData $_
                }
            }
        }

        if ($RuleStateIsCorrect -eq $false) {
            $cmdparams = @{
                Priority                  = 0
                RecipientDomainIs         = $AcceptedDomains.Name
            }

            if ($RuleState.HostedContentFilterPolicy -ne $PolicyName) {
                $cmdparams.Add('HostedContentFilterPolicy', $PolicyName)
            }

            if ($RuleState.Name -eq $PolicyName) {
                try {
                    $cmdparams.Add('Identity', "$PolicyName")
                    New-ExoRequest -TenantId $Tenant -cmdlet 'Set-HostedContentFilterRule' -cmdparams $cmdparams -UseSystemMailbox $true
                    Write-LogMessage -API 'Standards' -Tenant $Tenant -message "Updated Spam Filter rule $PolicyName." -sev Info
                } catch {
                    Write-LogMessage -API 'Standards' -Tenant $Tenant -message "Failed to update Spam Filter rule $PolicyName." -sev Error -LogData $_
                }
            } else {
                try {
                    $cmdparams.Add('Name', "$PolicyName")
                    New-ExoRequest -TenantId $Tenant -cmdlet 'New-HostedContentFilterRule' -cmdparams $cmdparams -UseSystemMailbox $true
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
            Write-LogMessage -API 'Standards' -Tenant $Tenant -message 'Spam Filter Policy is not enabled' -sev Alert
        }
    }

    if ($Settings.report -eq $true) {
        Add-CIPPBPAField -FieldName 'SpamFilterPolicy' -FieldValue $StateIsCorrect -StoreAs bool -Tenant $tenant
    }

}
