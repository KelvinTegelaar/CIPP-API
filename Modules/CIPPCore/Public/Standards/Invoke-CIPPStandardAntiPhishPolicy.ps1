function Invoke-CIPPStandardAntiPhishPolicy {
    <#
    .FUNCTIONALITY
        Internal
    .COMPONENT
        (APIName) AntiPhishPolicy
    .SYNOPSIS
        (Label) Default Anti-Phishing Policy
    .DESCRIPTION
        (Helptext) This creates a Anti-Phishing policy that automatically enables Mailbox Intelligence and spoofing, optional switches for Mailtips.
        (DocsDescription) This creates a Anti-Phishing policy that automatically enables Mailbox Intelligence and spoofing, optional switches for Mailtips.
    .NOTES
        CAT
            Defender Standards
        TAG
            "CIS"
            "mdo_safeattachments"
            "mdo_highconfidencespamaction"
            "mdo_highconfidencephishaction"
            "mdo_phisspamacation"
            "mdo_spam_notifications_only_for_admins"
            "mdo_antiphishingpolicies"
            "mdo_phishthresholdlevel"
        ADDEDCOMPONENT
            {"type":"number","label":"Phishing email threshold. (Default 1)","name":"standards.AntiPhishPolicy.PhishThresholdLevel","defaultValue":1}
            {"type":"switch","label":"Show first contact safety tip","name":"standards.AntiPhishPolicy.EnableFirstContactSafetyTips","defaultValue":true}
            {"type":"switch","label":"Show user impersonation safety tip","name":"standards.AntiPhishPolicy.EnableSimilarUsersSafetyTips","defaultValue":true}
            {"type":"switch","label":"Show domain impersonation safety tip","name":"standards.AntiPhishPolicy.EnableSimilarDomainsSafetyTips","defaultValue":true}
            {"type":"switch","label":"Show user impersonation unusual characters safety tip","name":"standards.AntiPhishPolicy.EnableUnusualCharactersSafetyTips","defaultValue":true}
            {"type":"select","multiple":false,"label":"If the message is detected as spoof by spoof intelligence","name":"standards.AntiPhishPolicy.AuthenticationFailAction","options":[{"label":"Quarantine the message","value":"Quarantine"},{"label":"Move to Junk Folder","value":"MoveToJmf"}]}
            {"type":"select","multiple":false,"label":"Quarantine policy for Spoof","name":"standards.AntiPhishPolicy.SpoofQuarantineTag","options":[{"label":"AdminOnlyAccessPolicy","value":"AdminOnlyAccessPolicy"},{"label":"DefaultFullAccessPolicy","value":"DefaultFullAccessPolicy"},{"label":"DefaultFullAccessWithNotificationPolicy","value":"DefaultFullAccessWithNotificationPolicy"}]}
            {"type":"select","multiple":false,"label":"If a message is detected as user impersonation","name":"standards.AntiPhishPolicy.TargetedUserProtectionAction","options":[{"label":"Move to Junk Folder","value":"MoveToJmf"},{"label":"Delete the message before its delivered","value":"Delete"},{"label":"Quarantine the message","value":"Quarantine"}]}
            {"type":"select","multiple":false,"label":"Quarantine policy for user impersonation","name":"standards.AntiPhishPolicy.TargetedUserQuarantineTag","options":[{"label":"AdminOnlyAccessPolicy","value":"AdminOnlyAccessPolicy"},{"label":"DefaultFullAccessPolicy","value":"DefaultFullAccessPolicy"},{"label":"DefaultFullAccessWithNotificationPolicy","value":"DefaultFullAccessWithNotificationPolicy"}]}
            {"type":"select","multiple":false,"label":"If a message is detected as domain impersonation","name":"standards.AntiPhishPolicy.TargetedDomainProtectionAction","options":[{"label":"Move to Junk Folder","value":"MoveToJmf"},{"label":"Delete the message before its delivered","value":"Delete"},{"label":"Quarantine the message","value":"Quarantine"}]}
            {"type":"select","multiple":false,"label":"Quarantine policy for domain impersonation","name":"standards.AntiPhishPolicy.TargetedDomainQuarantineTag","options":[{"label":"DefaultFullAccessWithNotificationPolicy","value":"DefaultFullAccessWithNotificationPolicy"},{"label":"AdminOnlyAccessPolicy","value":"AdminOnlyAccessPolicy"},{"label":"DefaultFullAccessPolicy","value":"DefaultFullAccessPolicy"}]}
            {"type":"select","multiple":false,"label":"If Mailbox Intelligence detects an impersonated user","name":"standards.AntiPhishPolicy.MailboxIntelligenceProtectionAction","options":[{"label":"Move to Junk Folder","value":"MoveToJmf"},{"label":"Delete the message before its delivered","value":"Delete"},{"label":"Quarantine the message","value":"Quarantine"}]}
            {"type":"select","multiple":false,"label":"Apply quarantine policy","name":"standards.AntiPhishPolicy.MailboxIntelligenceQuarantineTag","options":[{"label":"AdminOnlyAccessPolicy","value":"AdminOnlyAccessPolicy"},{"label":"DefaultFullAccessPolicy","value":"DefaultFullAccessPolicy"},{"label":"DefaultFullAccessWithNotificationPolicy","value":"DefaultFullAccessWithNotificationPolicy"}]}
        IMPACT
            Low Impact
        ADDEDDATE
            2024-03-25
        POWERSHELLEQUIVALENT
            Set-AntiphishPolicy or New-AntiphishPolicy
        RECOMMENDEDBY
            "CIS"
        UPDATECOMMENTBLOCK
            Run the Tools\Update-StandardsComments.ps1 script to update this comment block
    .LINK
        https://docs.cipp.app/user-documentation/tenant/standards/list-standards/defender-standards#low-impact
    #>

    param($Tenant, $Settings)
    ##$Rerun -Type Standard -Tenant $Tenant -Settings $Settings 'AntiPhishPolicy'

    $ServicePlans = New-GraphGetRequest -uri 'https://graph.microsoft.com/beta/subscribedSkus?$select=servicePlans' -tenantid $Tenant
    $ServicePlans = $ServicePlans.servicePlans.servicePlanName
    $MDOLicensed = $ServicePlans -contains "ATP_ENTERPRISE"
    Write-Information "MDOLicensed: $MDOLicensed"

    $PolicyList = @('CIPP Default Anti-Phishing Policy','Default Anti-Phishing Policy')
    $ExistingPolicy = New-ExoRequest -tenantid $Tenant -cmdlet 'Get-AntiPhishPolicy' | Where-Object -Property Name -In $PolicyList
    if ($null -eq $ExistingPolicy.Name) {
        $PolicyName = $PolicyList[0]
    } else {
        $PolicyName = $ExistingPolicy.Name
    }
    $RuleList = @( 'CIPP Default Anti-Phishing Rule','CIPP Default Anti-Phishing Policy')
    $ExistingRule = New-ExoRequest -tenantid $Tenant -cmdlet 'Get-AntiPhishRule' | Where-Object -Property Name -In $RuleList
    if ($null -eq $ExistingRule.Name) {
        $RuleName = $RuleList[0]
    } else {
        $RuleName = $ExistingRule.Name
    }

    $CurrentState = $ExistingPolicy |
        Select-Object Name, Enabled, PhishThresholdLevel, EnableMailboxIntelligence, EnableMailboxIntelligenceProtection, EnableSpoofIntelligence, EnableFirstContactSafetyTips, EnableSimilarUsersSafetyTips, EnableSimilarDomainsSafetyTips, EnableUnusualCharactersSafetyTips, EnableUnauthenticatedSender, EnableViaTag, AuthenticationFailAction, SpoofQuarantineTag, MailboxIntelligenceProtectionAction, MailboxIntelligenceQuarantineTag, TargetedUserProtectionAction, TargetedUserQuarantineTag, TargetedDomainProtectionAction, TargetedDomainQuarantineTag, EnableOrganizationDomainsProtection

    if ($MDOLicensed) {
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
                          ($CurrentState.AuthenticationFailAction -eq $Settings.AuthenticationFailAction) -and
                          ($CurrentState.SpoofQuarantineTag -eq $Settings.SpoofQuarantineTag) -and
                          ($CurrentState.MailboxIntelligenceProtectionAction -eq $Settings.MailboxIntelligenceProtectionAction) -and
                          ($CurrentState.MailboxIntelligenceQuarantineTag -eq $Settings.MailboxIntelligenceQuarantineTag) -and
                          ($CurrentState.TargetedUserProtectionAction -eq $Settings.TargetedUserProtectionAction) -and
                          ($CurrentState.TargetedUserQuarantineTag -eq $Settings.TargetedUserQuarantineTag) -and
                          ($CurrentState.TargetedDomainProtectionAction -eq $Settings.TargetedDomainProtectionAction) -and
                          ($CurrentState.TargetedDomainQuarantineTag -eq $Settings.TargetedDomainQuarantineTag) -and
                          ($CurrentState.EnableOrganizationDomainsProtection -eq $true)
    } else {
        $StateIsCorrect = ($CurrentState.Name -eq $PolicyName) -and
                          ($CurrentState.Enabled -eq $true) -and
                          ($CurrentState.EnableSpoofIntelligence -eq $true) -and
                          ($CurrentState.EnableFirstContactSafetyTips -eq $Settings.EnableFirstContactSafetyTips) -and
                          ($CurrentState.EnableUnauthenticatedSender -eq $true) -and
                          ($CurrentState.EnableViaTag -eq $true) -and
                          ($CurrentState.AuthenticationFailAction -eq $Settings.AuthenticationFailAction) -and
                          ($CurrentState.SpoofQuarantineTag -eq $Settings.SpoofQuarantineTag)
    }

    $AcceptedDomains = New-ExoRequest -tenantid $Tenant -cmdlet 'Get-AcceptedDomain'

    $RuleState = New-ExoRequest -tenantid $Tenant -cmdlet 'Get-AntiPhishRule' |
        Where-Object -Property Name -EQ $RuleName |
        Select-Object Name, AntiPhishPolicy, Priority, RecipientDomainIs

    $RuleStateIsCorrect = ($RuleState.Name -eq $RuleName) -and
                          ($RuleState.AntiPhishPolicy -eq $PolicyName) -and
                          ($RuleState.Priority -eq 0) -and
                          (!(Compare-Object -ReferenceObject $RuleState.RecipientDomainIs -DifferenceObject $AcceptedDomains.Name))

    if ($Settings.remediate -eq $true) {
        if ($StateIsCorrect -eq $true) {
            Write-LogMessage -API 'Standards' -tenant $Tenant -message 'Anti-phishing policy already correctly configured' -sev Info
        } else {
            if ($MDOLicensed) {
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
                    AuthenticationFailAction            = $Settings.AuthenticationFailAction
                    SpoofQuarantineTag                  = $Settings.SpoofQuarantineTag
                    MailboxIntelligenceProtectionAction = $Settings.MailboxIntelligenceProtectionAction
                    MailboxIntelligenceQuarantineTag    = $Settings.MailboxIntelligenceQuarantineTag
                    TargetedUserProtectionAction        = $Settings.TargetedUserProtectionAction
                    TargetedUserQuarantineTag           = $Settings.TargetedUserQuarantineTag
                    TargetedDomainProtectionAction      = $Settings.TargetedDomainProtectionAction
                    TargetedDomainQuarantineTag         = $Settings.TargetedDomainQuarantineTag
                    EnableOrganizationDomainsProtection = $true
                }
            } else {
                $cmdparams = @{
                    Enabled                             = $true
                    EnableSpoofIntelligence             = $true
                    EnableFirstContactSafetyTips        = $Settings.EnableFirstContactSafetyTips
                    EnableUnauthenticatedSender         = $true
                    EnableViaTag                        = $true
                    AuthenticationFailAction            = $Settings.AuthenticationFailAction
                    SpoofQuarantineTag                  = $Settings.SpoofQuarantineTag
                }
            }

            if ($CurrentState.Name -eq $PolicyName) {
                try {
                    $cmdparams.Add('Identity', $PolicyName)
                    New-ExoRequest -tenantid $Tenant -cmdlet 'Set-AntiPhishPolicy' -cmdparams $cmdparams -UseSystemMailbox $true
                    Write-LogMessage -API 'Standards' -tenant $Tenant -message "Updated Anti-phishing policy $PolicyName." -sev Info
                } catch {
                    Write-LogMessage -API 'Standards' -tenant $Tenant -message "Failed to update Anti-phishing policy $PolicyName." -sev Error -LogData $_
                }
            } else {
                try {
                    $cmdparams.Add('Name', $PolicyName)
                    New-ExoRequest -tenantid $Tenant -cmdlet 'New-AntiPhishPolicy' -cmdparams $cmdparams -UseSystemMailbox $true
                    Write-LogMessage -API 'Standards' -tenant $Tenant -message "Created Anti-phishing policy $PolicyName." -sev Info
                } catch {
                    Write-LogMessage -API 'Standards' -tenant $Tenant -message "Failed to create Anti-phishing policy $PolicyName." -sev Error -LogData $_
                }
            }
        }

        if ($RuleStateIsCorrect -eq $false) {
            $cmdparams = @{
                Priority          = 0
                RecipientDomainIs = $AcceptedDomains.Name
            }

            if ($RuleState.AntiPhishPolicy -ne $PolicyName) {
                $cmdparams.Add('AntiPhishPolicy', $PolicyName)
            }

            if ($RuleState.Name -eq $RuleName) {
                try {
                    $cmdparams.Add('Identity', $RuleName)
                    New-ExoRequest -tenantid $Tenant -cmdlet 'Set-AntiPhishRule' -cmdparams $cmdparams -UseSystemMailbox $true
                    Write-LogMessage -API 'Standards' -tenant $Tenant -message "Updated Anti-phishing rule $RuleName." -sev Info
                } catch {
                    Write-LogMessage -API 'Standards' -tenant $Tenant -message "Failed to update Anti-phishing rule $RuleName." -sev Error -LogData $_
                }
            } else {
                try {
                    $cmdparams.Add('Name', $RuleName)
                    New-ExoRequest -tenantid $Tenant -cmdlet 'New-AntiPhishRule' -cmdparams $cmdparams -UseSystemMailbox $true
                    Write-LogMessage -API 'Standards' -tenant $Tenant -message "Created Anti-phishing rule $RuleName." -sev Info
                } catch {
                    Write-LogMessage -API 'Standards' -tenant $Tenant -message "Failed to create Anti-phishing rule $RuleName." -sev Error -LogData $_
                }
            }
        }
    }

    if ($Settings.alert -eq $true) {

        if ($StateIsCorrect -eq $true) {
            Write-LogMessage -API 'Standards' -tenant $Tenant -message 'Anti-phishing policy is enabled' -sev Info
        } else {
            Write-LogMessage -API 'Standards' -tenant $Tenant -message 'Anti-phishing policy is not enabled' -sev Alert
        }
    }

    if ($Settings.report -eq $true) {
        Add-CIPPBPAField -FieldName 'AntiPhishPolicy' -FieldValue $StateIsCorrect -StoreAs bool -Tenant $tenant
    }

}
