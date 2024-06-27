function Invoke-CIPPStandardAntiPhishPolicy {
    <#
    .FUNCTIONALITY
    Internal
    #>

    param($Tenant, $Settings)
    $PolicyName = 'Default Anti-Phishing Policy'

    $CurrentState = New-ExoRequest -tenantid $Tenant -cmdlet 'Get-AntiPhishPolicy' |
        Where-Object -Property Name -EQ $PolicyName |
        Select-Object Name, Enabled, PhishThresholdLevel, EnableMailboxIntelligence, EnableMailboxIntelligenceProtection, EnableSpoofIntelligence, EnableFirstContactSafetyTips, EnableSimilarUsersSafetyTips, EnableSimilarDomainsSafetyTips, EnableUnusualCharactersSafetyTips, EnableUnauthenticatedSender, EnableViaTag, MailboxIntelligenceProtectionAction, MailboxIntelligenceQuarantineTag

    $StateIsCorrect = ($CurrentState.Name -eq $PolicyName) -and
                      ($CurrentState.Enabled -eq $true) -and
                      ($CurrentState.PhishThresholdLevel -eq $Settings.PhishThresholdLevel) -and
                      ($CurrentState.EnableMailboxIntelligence -eq $true) -and
                      ($CurrentState.EnableMailboxIntelligenceProtection -eq $true) -and
                      ($CurrentState.EnableSpoofIntelligence -eq $true) -and
                      ($CurrentState.EnableFirstContactSafetyTips -eq $Settings.EnableFirstContactSafetyTips) -and
                      ($CurrentState.EnableSimilarUsersSafetyTips -eq $Settings.EnableSimilarUsersSafetyTips) -and
                      ($CurrentState.EnableSimilarDomainsSafetyTips -eq $Settings.EnableSimilarDomainsSafetyTips) -and
                      ($CurrentState.EnableUnusualCharactersSafetyTips -eq $Settings.EnableUnusualCharactersSafetyTips) -and
                      ($CurrentState.EnableUnauthenticatedSender -eq $true) -and
                      ($CurrentState.EnableViaTag -eq $true) -and
                      ($CurrentState.MailboxIntelligenceProtectionAction -eq $Settings.MailboxIntelligenceProtectionAction) -and
                      ($CurrentState.MailboxIntelligenceQuarantineTag -eq $Settings.MailboxIntelligenceQuarantineTag) -and
                      ($CurrentState.TargetedUserProtectionAction -eq $Settings.TargetedUserProtectionAction) -and
                      ($CurrentState.TargetedDomainProtectionAction -eq $Settings.TargetedDomainProtectionAction) -and
                      ($CurrentState.EnableOrganizationDomainsProtection -eq $true)

    $AcceptedDomains = New-ExoRequest -tenantid $Tenant -cmdlet 'Get-AcceptedDomain'

    $RuleState = New-ExoRequest -tenantid $Tenant -cmdlet 'Get-AntiPhishRule' |
        Where-Object -Property Name -EQ "CIPP $PolicyName" |
        Select-Object Name, AntiPhishPolicy, Priority, RecipientDomainIs

    $RuleStateIsCorrect = ($RuleState.Name -eq "CIPP $PolicyName") -and
                          ($RuleState.AntiPhishPolicy -eq $PolicyName) -and
                          ($RuleState.Priority -eq 0) -and
                          (!(Compare-Object -ReferenceObject $RuleState.RecipientDomainIs -DifferenceObject $AcceptedDomains.Name))

    if ($Settings.remediate -eq $true) {
        if ($StateIsCorrect -eq $true) {
            Write-LogMessage -API 'Standards' -tenant $Tenant -message 'Anti-phishing Policy already correctly configured' -sev Info
        } else {
            $cmdparams = @{
                Enabled                             = $true
                PhishThresholdLevel                 = $Settings.PhishThresholdLevel
                EnableMailboxIntelligence           = $true
                EnableMailboxIntelligenceProtection = $true
                EnableSpoofIntelligence             = $true
                EnableFirstContactSafetyTips        = $Settings.EnableFirstContactSafetyTips
                EnableSimilarUsersSafetyTips        = $Settings.EnableSimilarUsersSafetyTips
                EnableSimilarDomainsSafetyTips      = $Settings.EnableSimilarDomainsSafetyTips
                EnableUnusualCharactersSafetyTips   = $Settings.EnableUnusualCharactersSafetyTips
                EnableUnauthenticatedSender         = $true
                EnableViaTag                        = $true
                MailboxIntelligenceProtectionAction = $Settings.MailboxIntelligenceProtectionAction
                MailboxIntelligenceQuarantineTag    = $Settings.MailboxIntelligenceQuarantineTag
                TargetedUserProtectionAction        = $Settings.TargetedUserProtectionAction
                TargetedDomainProtectionAction      = $Settings.TargetedDomainProtectionAction
                EnableOrganizationDomainsProtection = $true
            }

            if ($CurrentState.Name -eq $PolicyName) {
                try {
                    $cmdparams.Add('Identity', $PolicyName)
                    New-ExoRequest -tenantid $Tenant -cmdlet 'Set-AntiPhishPolicy' -cmdparams $cmdparams -UseSystemMailbox $true
                    Write-LogMessage -API 'Standards' -tenant $Tenant -message 'Updated Anti-phishing Policy' -sev Info
                } catch {
                    $ErrorMessage = Get-NormalizedError -Message $_.Exception.Message
                    Write-LogMessage -API 'Standards' -tenant $Tenant -message "Failed to update Anti-phishing Policy. Error: $ErrorMessage" -sev Error
                }
            } else {
                try {
                    $cmdparams.Add('Name', $PolicyName)
                    New-ExoRequest -tenantid $Tenant -cmdlet 'New-AntiPhishPolicy' -cmdparams $cmdparams -UseSystemMailbox $true
                    Write-LogMessage -API 'Standards' -tenant $Tenant -message 'Created Anti-phishing Policy' -sev Info
                } catch {
                    $ErrorMessage = Get-NormalizedError -Message $_.Exception.Message
                    Write-LogMessage -API 'Standards' -tenant $Tenant -message "Failed to create Anti-phishing Policy. Error: $ErrorMessage" -sev Error
                }
            }
        }

        if ($RuleStateIsCorrect -eq $false) {
            $cmdparams = @{
                AntiPhishPolicy   = $PolicyName
                Priority          = 0
                RecipientDomainIs = $AcceptedDomains.Name
            }

            if ($RuleState.Name -eq "CIPP $PolicyName") {
                try {
                    $cmdparams.Add('Identity', "CIPP $PolicyName")
                    New-ExoRequest -tenantid $Tenant -cmdlet 'Set-AntiPhishRule' -cmdparams $cmdparams -UseSystemMailbox $true
                    Write-LogMessage -API 'Standards' -tenant $Tenant -message 'Updated Anti-phishing Rule' -sev Info
                } catch {
                    $ErrorMessage = Get-NormalizedError -Message $_.Exception.Message
                    Write-LogMessage -API 'Standards' -tenant $Tenant -message "Failed to update Anti-phishing Rule. Error: $ErrorMessage" -sev Error
                }
            } else {
                try {
                    $cmdparams.Add('Name', "CIPP $PolicyName")
                    New-ExoRequest -tenantid $Tenant -cmdlet 'New-AntiPhishRule' -cmdparams $cmdparams -UseSystemMailbox $true
                    Write-LogMessage -API 'Standards' -tenant $Tenant -message 'Created Anti-phishing Rule' -sev Info
                } catch {
                    $ErrorMessage = Get-NormalizedError -Message $_.Exception.Message
                    Write-LogMessage -API 'Standards' -tenant $Tenant -message "Failed to create Anti-phishing Rule. Error: $ErrorMessage" -sev Error
                }
            }
        }
    }

    if ($Settings.alert -eq $true) {

        if ($StateIsCorrect -eq $true) {
            Write-LogMessage -API 'Standards' -tenant $Tenant -message 'Anti-phishing Policy is enabled' -sev Info
        } else {
            Write-LogMessage -API 'Standards' -tenant $Tenant -message 'Anti-phishing Policy is not enabled' -sev Alert
        }
    }

    if ($Settings.report -eq $true) {
        Add-CIPPBPAField -FieldName 'AntiPhishPolicy' -FieldValue $StateIsCorrect -StoreAs bool -Tenant $tenant
    }

}
