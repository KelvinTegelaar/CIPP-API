function Invoke-CIPPStandardAntiPhishPolicy {
    <#
    .FUNCTIONALITY
    Internal
    #>

    param($Tenant, $Settings)
    $AntiPhishPolicyState = New-ExoRequest -tenantid $Tenant -cmdlet 'Get-AntiPhishPolicy' | 
    Where-Object -Property Name -eq "Office365 AntiPhish Default" | 
    Select-Object Name, Enabled, PhishThresholdLevel, EnableMailboxIntelligence, EnableMailboxIntelligenceProtection, EnableSpoofIntelligence, EnableFirstContactSafetyTips, EnableSimilarUsersSafetyTips, EnableSimilarDomainsSafetyTips, EnableUnusualCharactersSafetyTips, EnableUnauthenticatedSender, EnableViaTag, MailboxIntelligenceProtectionAction, MailboxIntelligenceQuarantineTag

    $StateIsCorrect = if (
        ($AntiPhishPolicyState.Name -eq "Office365 AntiPhish Default") -and
        ($AntiPhishPolicyState.Enabled -eq $Settings.Enabled) -and 
        ($AntiPhishPolicyState.PhishThresholdLevel -eq $Settings.PhishThresholdLevel) -and
        ($AntiPhishPolicyState.EnableMailboxIntelligence -eq $Settings.EnableMailboxIntelligence) -and
        ($AntiPhishPolicyState.EnableMailboxIntelligenceProtection -eq $Settings.EnableMailboxIntelligenceProtection) -and
        ($AntiPhishPolicyState.EnableSpoofIntelligence -eq $Settings.EnableSpoofIntelligence) -and
        ($AntiPhishPolicyState.EnableFirstContactSafetyTips -eq $Settings.EnableFirstContactSafetyTips) -and
        ($AntiPhishPolicyState.EnableSimilarUsersSafetyTips -eq $Settings.EnableSimilarUsersSafetyTips) -and
        ($AntiPhishPolicyState.EnableSimilarDomainsSafetyTips -eq $Settings.EnableSimilarDomainsSafetyTips) -and
        ($AntiPhishPolicyState.EnableUnusualCharactersSafetyTips -eq $Settings.EnableUnusualCharactersSafetyTips) -and
        ($AntiPhishPolicyState.EnableUnauthenticatedSender -eq $Settings.EnableUnauthenticatedSender) -and
        ($AntiPhishPolicyState.EnableViaTag -eq $Settings.EnableViaTag) -and
        ($AntiPhishPolicyState.MailboxIntelligenceProtectionAction -eq $Settings.MailboxIntelligenceProtectionAction) -and
        ($AntiPhishPolicyState.MailboxIntelligenceQuarantineTag -eq $Settings.MailboxIntelligenceQuarantineTag)
    ) { $true } else { $false }

    if ($Settings.remediate) {
        if ($StateIsCorrect) {
            Write-LogMessage -API 'Standards' -tenant $Tenant -message 'Anti-phishing Policy already exists.' -sev Info
        } else {
            $cmdparams = @{
                Enabled = $Settings.Enabled
                PhishThresholdLevel = $Settings.PhishThresholdLevel
                EnableMailboxIntelligence = $Settings.EnableMailboxIntelligence
                EnableMailboxIntelligenceProtection = $Settings.EnableMailboxIntelligenceProtection
                EnableSpoofIntelligence = $Settings.EnableSpoofIntelligence
                EnableFirstContactSafetyTips = $Settings.EnableFirstContactSafetyTips
                EnableSimilarUsersSafetyTips = $Settings.EnableSimilarUsersSafetyTips
                EnableSimilarDomainsSafetyTips = $Settings.EnableSimilarDomainsSafetyTips
                EnableUnusualCharactersSafetyTips = $Settings.EnableUnusualCharactersSafetyTips
                EnableUnauthenticatedSender = $Settings.EnableUnauthenticatedSender
                EnableViaTag = $Settings.EnableViaTag
                MailboxIntelligenceProtectionAction = $Settings.MailboxIntelligenceProtectionAction
                MailboxIntelligenceQuarantineTag = $Settings.MailboxIntelligenceQuarantineTag
            }

            try {
                if ($AntiPhishPolicyState.Name -eq "Office365 AntiPhish Default") {
                    $cmdparams.Add("Identity", "Office365 AntiPhish Default")
                    New-ExoRequest -tenantid $Tenant -cmdlet 'Set-AntiPhishPolicy' -cmdparams $cmdparams
                    Write-LogMessage -API 'Standards' -tenant $Tenant -message 'Updated Anti-phishing Policy' -sev Info
                } else {
                    $cmdparams.Add("Name", "Office365 AntiPhish Default")
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