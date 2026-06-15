function Invoke-CIPPStandardOMEBranding {
    <#
    .FUNCTIONALITY
        Internal
    .COMPONENT
        (APIName) OMEBranding
    .SYNOPSIS
        (Label) Configure Encrypted Message Branding (OME)
    .DESCRIPTION
        (Helptext) Configures the branding applied to Microsoft Purview (OME) encrypted emails, including the logo, background color, and the text recipients see when viewing a protected message. [Read more](https://learn.microsoft.com/en-us/purview/add-your-organization-brand-to-encrypted-messages)
        (DocsDescription) Configures Office Message Encryption (OME) branding settings for the tenant default configuration. Allows organizations to apply a custom logo (via URL), background color, button text, and portal text to encrypted emails viewed by external recipients.
    .NOTES
        CAT
            Exchange Standards
        TAG
        EXECUTIVETEXT
            Applies organizational branding to encrypted emails so recipients see a professional, on-brand experience when viewing protected messages. Reinforces brand identity while preserving security compliance.
        ADDEDCOMPONENT
            {"type": "textField","name": "standards.OMEBranding.BackgroundColor","label": "Background Color - Optional","placeholder": "#ffffff","helpText": "The background color of the encrypted message wrapper. Enter an HTML hex color code (e.g. #ffffff) or a named color value (e.g. white).","required": false},
            {"type": "textField","name": "standards.OMEBranding.LogoUrl","label": "Logo Image URL - Optional (Less than 40kb 170x70 pixels)","placeholder": "https://example.com/logo.png or %CustomVarable%","helpText": "URL to your organization's logo displayed in the encrypted email and the reading portal. Supported formats: PNG, JPG, BMP, TIFF. Optimal size: 170x70 px, max 40 KB.","required": false},
            {"type": "textField","name": "standards.OMEBranding.IntroductionText","label": "Text next to the sender's name and email address - Optional","placeholder": "has sent you a secure message.","helpText": "Text that appears next to the sender's name and email address. Maximum 1024 characters.","required": false},
            {"type": "textField","name": "standards.OMEBranding.ReadButtonText","label": "Read Button Text - Optional","placeholder": "Read Secure Message.","helpText": "Text that appears on the 'Read Message' button. Maximum 1024 characters.","required": false},
            {"type": "textField","name": "standards.OMEBranding.EmailText","label": "Email Text below the button - Optional","placeholder": "Encrypted message from Contoso secure messaging system.","helpText": "Text that appears below the 'Read Message' button. Maximum 1024 characters.","required": false},
            {"type": "textField","name": "standards.OMEBranding.PrivacyStatementUrl","label": "Privacy Statement URL - Optional","placeholder": "https://contoso.com/privacystatement.html","helpText": "URL for the Privacy Statement link in the encrypted email notification. Leave blank to use Microsoft's default privacy statement.","required": false},
            {"type": "textField","name": "standards.OMEBranding.DisclaimerText","label": "Disclaimer Statement  - Optional","placeholder": "This message is confidential for the use of the addressee only.","helpText": "Disclaimer statement shown in the email that contains the encrypted message. Maximum 1024 characters.","required": false},
            {"type": "textField","name": "standards.OMEBranding.PortalText","label": "Text appears at the top of the encrypted mail viewing portal  - Optional","placeholder": "Contoso secure email portal.","helpText": "Text that appears at the top of the encrypted mail viewing portal. Maximum 128 characters.","required": false},
            {"type": "autoComplete","multiple": false,"creatable": false,"name": "standards.OMEBranding.OTPEnabled","label": "One-Time Pass Code - Required","helpText": "Enable or disable authentication with a one-time pass code. When enabled, recipients without a Microsoft account can verify their identity via a code sent to their email.","options": [{"label": "Enabled","value": true},{"label": "Disabled","value": false}]},
            {"type": "autoComplete","multiple": false,"creatable": false,"name": "standards.OMEBranding.SocialIdSignIn","label": "Social ID Sign-In - Required","helpText": "Enable or disable authentication with Microsoft, Google, or Yahoo identities. When enabled, recipients can sign in with an existing social account to view the encrypted message.","options": [{"label": "Enabled","value": true},{"label": "Disabled","value": false}]}
        IMPACT
            Low Impact
        ADDEDDATE
            2026-04-25
        POWERSHELLEQUIVALENT
            Set-OMEConfiguration
        RECOMMENDEDBY
            "CIPP"
        UPDATECOMMENTBLOCK
            Run the Tools\Update-StandardsComments.ps1 script to update this comment block
    .LINK
        https://docs.cipp.app/user-documentation/tenant/standards/alignment/templates/available-standards
    #>      

    param($Tenant, $Settings)
    $TestResult = Test-CIPPStandardLicense -StandardName 'OMEBranding' -TenantFilter $Tenant -Preset Exchange

    if ($TestResult -eq $false) {
        return $true
    }

    try {
        $CurrentState = New-ExoRequest -tenantid $Tenant -cmdlet 'Get-OMEConfiguration' -cmdParams @{ Identity = 'OME Configuration' }
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Write-LogMessage -API 'Standards' -Tenant $Tenant -Message "Could not get encrypted message branding (OME) configuration for $Tenant. Error: $($ErrorMessage.NormalizedError)" -Sev Error -LogData $ErrorMessage
        return
    }

    $SetParams = @{ Identity = if ($CurrentState.Identity) { $CurrentState.Identity } else { 'OME Configuration' } }

    $OTPEnabled = if ($null -ne $Settings.OTPEnabled) { [bool]($Settings.OTPEnabled.value ?? $Settings.OTPEnabled) } else { $null }
    $SocialIdSignIn = if ($null -ne $Settings.SocialIdSignIn) { [bool]($Settings.SocialIdSignIn.value ?? $Settings.SocialIdSignIn) } else { $null }

    if ($Settings.BackgroundColor) { $SetParams['BackgroundColor'] = $Settings.BackgroundColor }
    if ($Settings.EmailText) { $SetParams['EmailText'] = $Settings.EmailText }
    if ($Settings.IntroductionText) { $SetParams['IntroductionText'] = $Settings.IntroductionText }
    if ($Settings.ReadButtonText) { $SetParams['ReadButtonText'] = $Settings.ReadButtonText }
    if ($Settings.PortalText) { $SetParams['PortalText'] = $Settings.PortalText }
    if ($Settings.DisclaimerText) { $SetParams['DisclaimerText'] = $Settings.DisclaimerText }
    if ($Settings.PrivacyStatementUrl) { $SetParams['PrivacyStatementUrl'] = $Settings.PrivacyStatementUrl }
    if ($null -ne $OTPEnabled) { $SetParams['OTPEnabled'] = $OTPEnabled }
    if ($null -ne $SocialIdSignIn) { $SetParams['SocialIdSignIn'] = $SocialIdSignIn }

    $LogoFetched = $false
    if ($Settings.LogoUrl -and $Settings.LogoUrl -match '^https?://') {
        try {
            $SetParams['Image'] = (Invoke-WebRequest -Uri $Settings.LogoUrl -UseBasicParsing).Content
            $LogoFetched = $true
        } catch {
            $ErrorMessage = Get-CippException -Exception $_
            Write-LogMessage -API 'Standards' -Tenant $Tenant -Message "Could not fetch logo from URL '$($Settings.LogoUrl)' for $Tenant. Existing logo left unchanged. Error: $($ErrorMessage.NormalizedError)" -Sev Warning -LogData $ErrorMessage
        }
    } elseif ($Settings.LogoUrl) {
        Write-LogMessage -API 'Standards' -Tenant $Tenant -Message "The Logo URL for $Tenant is not a valid URL (possibly an unresolved custom variable). Existing logo left unchanged." -Sev Warning
    }

    $StateIsCorrect = $true
    if ($Settings.BackgroundColor -and $CurrentState.BackgroundColor -ne $Settings.BackgroundColor) { $StateIsCorrect = $false }
    if ($Settings.EmailText -and $CurrentState.EmailText -ne $Settings.EmailText) { $StateIsCorrect = $false }
    if ($Settings.IntroductionText -and $CurrentState.IntroductionText -ne $Settings.IntroductionText) { $StateIsCorrect = $false }
    if ($Settings.ReadButtonText -and $CurrentState.ReadButtonText -ne $Settings.ReadButtonText) { $StateIsCorrect = $false }
    if ($Settings.PortalText -and $CurrentState.PortalText -ne $Settings.PortalText) { $StateIsCorrect = $false }
    if ($Settings.DisclaimerText -and $CurrentState.DisclaimerText -ne $Settings.DisclaimerText) { $StateIsCorrect = $false }
    if ($Settings.PrivacyStatementUrl -and $CurrentState.PrivacyStatementUrl -ne $Settings.PrivacyStatementUrl) { $StateIsCorrect = $false }
    if ($null -ne $OTPEnabled -and $CurrentState.OTPEnabled -ne $OTPEnabled) { $StateIsCorrect = $false }
    if ($null -ne $SocialIdSignIn -and $CurrentState.SocialIdSignIn -ne $SocialIdSignIn) { $StateIsCorrect = $false }
    if ($LogoFetched) { $StateIsCorrect = $false }

    if ($Settings.remediate -eq $true) {
        if ($StateIsCorrect) {
            Write-LogMessage -API 'Standards' -tenant $Tenant -message 'Encrypted message branding (OME) is already configured correctly.' -sev Info
        } else {
            try {
                New-ExoRequest -tenantid $Tenant -cmdlet 'Set-OMEConfiguration' -cmdParams $SetParams -useSystemMailbox $true
                Write-LogMessage -API 'Standards' -tenant $Tenant -message 'Applied encrypted message branding (OME) configuration.' -sev Info
            } catch {
                $ErrorMessage = Get-CippException -Exception $_
                Write-LogMessage -API 'Standards' -tenant $Tenant -message "Failed to apply encrypted message branding (OME) configuration. Error: $($ErrorMessage.NormalizedError)" -sev Error -LogData $ErrorMessage
            }
        }
    }

    if ($Settings.alert -eq $true) {
        if ($StateIsCorrect) {
            Write-LogMessage -API 'Standards' -tenant $Tenant -message 'Encrypted message branding (OME) is configured correctly.' -sev Info
        } else {
            Write-StandardsAlert -message 'Encrypted message branding (OME) is not configured as required.' -object $CurrentState -tenant $Tenant -standardName 'OMEBranding' -standardId $Settings.standardId
            Write-LogMessage -API 'Standards' -tenant $Tenant -message 'Encrypted message branding (OME) is not configured as required.' -sev Info
        }
    }

    if ($Settings.report -eq $true) {
        $CurrentLogoApplied = ($null -ne $CurrentState.Image -and $CurrentState.Image.Length -gt 0)
        $ReportCurrent = [PSCustomObject]@{
            BackgroundColor     = $CurrentState.BackgroundColor
            IntroductionText    = $CurrentState.IntroductionText
            ReadButtonText      = $CurrentState.ReadButtonText
            EmailText           = $CurrentState.EmailText
            PortalText          = $CurrentState.PortalText
            DisclaimerText      = $CurrentState.DisclaimerText
            PrivacyStatementUrl = $CurrentState.PrivacyStatementUrl
            OTPEnabled          = $CurrentState.OTPEnabled
            SocialIdSignIn      = $CurrentState.SocialIdSignIn
            CustomLogoApplied   = $CurrentLogoApplied
        }
        $ReportExpected = [PSCustomObject]@{
            BackgroundColor     = if ($Settings.BackgroundColor) { $Settings.BackgroundColor } else { $CurrentState.BackgroundColor }
            IntroductionText    = if ($Settings.IntroductionText) { $Settings.IntroductionText } else { $CurrentState.IntroductionText }
            ReadButtonText      = if ($Settings.ReadButtonText) { $Settings.ReadButtonText } else { $CurrentState.ReadButtonText }
            EmailText           = if ($Settings.EmailText) { $Settings.EmailText } else { $CurrentState.EmailText }
            PortalText          = if ($Settings.PortalText) { $Settings.PortalText } else { $CurrentState.PortalText }
            DisclaimerText      = if ($Settings.DisclaimerText) { $Settings.DisclaimerText } else { $CurrentState.DisclaimerText }
            PrivacyStatementUrl = if ($Settings.PrivacyStatementUrl) { $Settings.PrivacyStatementUrl } else { $CurrentState.PrivacyStatementUrl }
            OTPEnabled          = if ($null -ne $OTPEnabled) { $OTPEnabled } else { $CurrentState.OTPEnabled }
            SocialIdSignIn      = if ($null -ne $SocialIdSignIn) { $SocialIdSignIn } else { $CurrentState.SocialIdSignIn }
            CustomLogoApplied   = if ($Settings.LogoUrl -and $Settings.LogoUrl -match '^https?://') { $true } else { $CurrentLogoApplied }
        }
        Set-CIPPStandardsCompareField -FieldName 'standards.OMEBranding' -CurrentValue $ReportCurrent -ExpectedValue $ReportExpected -TenantFilter $Tenant
    }
}
