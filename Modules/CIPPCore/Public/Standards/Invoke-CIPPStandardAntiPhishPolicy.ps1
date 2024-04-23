function Invoke-CIPPStandardAntiPhishPolicy {
    <#
    .FUNCTIONALITY
    Internal
    #>

    param($Tenant, $Settings)
    $PolicyName = 'Default Anti-Phishing Policy'
    $AntiPhishPolicyState = New-ExoRequest -tenantid $Tenant -cmdlet 'Get-AntiPhishPolicy' | 
        Where-Object -Property Name -EQ $PolicyName | 
        Select-Object Name, Enabled, PhishThresholdLevel, EnableMailboxIntelligence, EnableMailboxIntelligenceProtection, EnableSpoofIntelligence, EnableFirstContactSafetyTips, EnableSimilarUsersSafetyTips, EnableSimilarDomainsSafetyTips, EnableUnusualCharactersSafetyTips, EnableUnauthenticatedSender, EnableViaTag, MailboxIntelligenceProtectionAction, MailboxIntelligenceQuarantineTag

    $StateIsCorrect = if (
        ($AntiPhishPolicyState.Name -eq $PolicyName) -and
        ($AntiPhishPolicyState.Enabled -eq $true) -and 
        ($AntiPhishPolicyState.PhishThresholdLevel -eq $Settings.PhishThresholdLevel) -and
        ($AntiPhishPolicyState.EnableMailboxIntelligence -eq $true) -and
        ($AntiPhishPolicyState.EnableMailboxIntelligenceProtection -eq $true) -and
        ($AntiPhishPolicyState.EnableSpoofIntelligence -eq $true) -and
        ($AntiPhishPolicyState.EnableFirstContactSafetyTips -eq $Settings.EnableFirstContactSafetyTips) -and
        ($AntiPhishPolicyState.EnableSimilarUsersSafetyTips -eq $Settings.EnableSimilarUsersSafetyTips) -and
        ($AntiPhishPolicyState.EnableSimilarDomainsSafetyTips -eq $Settings.EnableSimilarDomainsSafetyTips) -and
        ($AntiPhishPolicyState.EnableUnusualCharactersSafetyTips -eq $Settings.EnableUnusualCharactersSafetyTips) -and
        ($AntiPhishPolicyState.EnableUnauthenticatedSender -eq $true) -and
        ($AntiPhishPolicyState.EnableViaTag -eq $true) -and
        ($AntiPhishPolicyState.MailboxIntelligenceProtectionAction -eq $Settings.MailboxIntelligenceProtectionAction) -and
        ($AntiPhishPolicyState.MailboxIntelligenceQuarantineTag -eq $Settings.MailboxIntelligenceQuarantineTag)
    ) { $true } else { $false }

    if ($Settings.remediate) {
        if ($StateIsCorrect) {
            Write-LogMessage -API 'Standards' -tenant $Tenant -message 'Anti-phishing Policy already exists.' -sev Info
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
            }

            try {
                if ($AntiPhishPolicyState.Name -eq $PolicyName) {
                    $cmdparams.Add('Identity', $PolicyName)
                    New-ExoRequest -tenantid $Tenant -cmdlet 'Set-AntiPhishPolicy' -cmdparams $cmdparams
                    Write-LogMessage -API 'Standards' -tenant $Tenant -message 'Updated Anti-phishing Policy' -sev Info
                } else {
                    $cmdparams.Add('Name', $PolicyName)
                    New-ExoRequest -tenantid $Tenant -cmdlet 'New-AntiPhishPolicy' -cmdparams $cmdparams
                    Write-LogMessage -API 'Standards' -tenant $Tenant -message 'Created Anti-phishing Policy' -sev Info
                }
            } catch {
                Write-LogMessage -API 'Standards' -tenant $Tenant -message "Failed to create Anti-phishing Policy. Error: $($_.exception.message)" -sev Error
            }
        }
    }


    if ($Settings.alert) {

        if ($StateIsCorrect) {
            Write-LogMessage -API 'Standards' -tenant $Tenant -message 'Anti-phishing Policy is enabled' -sev Info
        } else {
            Write-LogMessage -API 'Standards' -tenant $Tenant -message 'Anti-phishing Policy is not enabled' -sev Alert
        }
    }

    if ($Settings.report) {
        Add-CIPPBPAField -FieldName 'AntiPhishPolicy' -FieldValue [bool]$StateIsCorrect -StoreAs bool -Tenant $tenant
    }
    
}