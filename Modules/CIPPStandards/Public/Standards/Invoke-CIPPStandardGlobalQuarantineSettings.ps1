function Invoke-CIPPStandardGlobalQuarantineSettings {
    <#
    .FUNCTIONALITY
        Internal
    .COMPONENT
        (APIName) GlobalQuarantineSettings
    .SYNOPSIS
        (Label) Configure Global Quarantine Notification Settings
    .DESCRIPTION
        (Helptext) Configures the Global Quarantine Policy settings including sender name, custom subject, disclaimer, from address, and org branding.
        (DocsDescription) Configures the Global Quarantine Policy branding and notification settings for the tenant. This includes the quarantine notification sender display name, custom subject line, disclaimer text, the from address used for notifications, and whether to use org branding. Notification frequency is managed separately by the GlobalQuarantineNotifications standard.
    .NOTES
        CAT
            Exchange Standards
        TAG
        EXECUTIVETEXT
            Ensures quarantine notification emails are branded and configured consistently, so end users receive clear, professional alerts about quarantined messages and know how to request release.
        ADDEDCOMPONENT
            {"type":"textField","name":"standards.GlobalQuarantineSettings.SenderName","label":"Sender Display Name (e.g. Contoso-Office365Alerts)","helperText":"Will be overridden if an active sender address with an existing display name is used.","required":false}
            {"type":"textField","name":"standards.GlobalQuarantineSettings.CustomSubject","label":"Subject","required":false}
            {"type":"textField","name":"standards.GlobalQuarantineSettings.CustomDisclaimer","label":"Disclaimer (max 200 characters)","required":false}
            {"type":"textField","name":"standards.GlobalQuarantineSettings.FromAddress","label":"Specify Sender Address (must be an internal mailbox)","required":false}
            {"type":"switch","name":"standards.GlobalQuarantineSettings.OrganizationBrandingEnabled","label":"Use Organization Branding (logo)","helperText":"Requires branding to be configured in the Microsoft 365 admin centre."}
        IMPACT
            Low Impact
        ADDEDDATE
            2026-04-02
        POWERSHELLEQUIVALENT
            Set-QuarantinePolicy (GlobalQuarantinePolicy)
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
        https://docs.cipp.app/user-documentation/tenant/standards/list-standards
    #>
    param($Tenant, $Settings)
    $TestResult = Test-CIPPStandardLicense -StandardName 'QuarantineTemplate' -TenantFilter $Tenant -RequiredCapabilities @('EXCHANGE_S_STANDARD', 'EXCHANGE_S_ENTERPRISE', 'EXCHANGE_S_STANDARD_GOV', 'EXCHANGE_S_ENTERPRISE_GOV', 'EXCHANGE_LITE') #No Foundation because that does not allow powershell access

    if ($TestResult -eq $false) {
        return $true
    } #we're done.

    try {
        $CurrentState = New-ExoRequest -tenantid $Tenant -cmdlet 'Get-QuarantinePolicy' -cmdParams @{ QuarantinePolicyType = 'GlobalQuarantinePolicy' } |
            Select-Object -ExcludeProperty '*data.type'
    } catch {
        $ErrorMessage = Get-NormalizedError -Message $_.Exception.Message
        Write-LogMessage -API 'Standards' -Tenant $Tenant -Message "Could not get the GlobalQuarantineSettings state for $Tenant. Error: $ErrorMessage" -Sev Error
        return
    }

    $SenderName       = $Settings.SenderName
    $CustomSubject    = $Settings.CustomSubject
    $CustomDisclaimer = $Settings.CustomDisclaimer
    $FromAddress      = $Settings.FromAddress
    $UseOrgBranding   = [bool]$Settings.OrganizationBrandingEnabled

    $ExistingLanguages = if ($CurrentState.MultiLanguageSetting -and $CurrentState.MultiLanguageSetting.Count -gt 0) {
        $CurrentState.MultiLanguageSetting
    } else {
        @('Default')
    }
    $LangCount   = $ExistingLanguages.Count
    $SenderNames = 1..$LangCount | ForEach-Object { $SenderName }
    $Subjects    = 1..$LangCount | ForEach-Object { $CustomSubject }
    $Disclaimers = 1..$LangCount | ForEach-Object { $CustomDisclaimer }

    $StateIsCorrect = (
        ($CurrentState.MultiLanguageSenderName        -contains $SenderName) -and
        ($CurrentState.ESNCustomSubject               -contains $CustomSubject) -and
        ($CurrentState.MultiLanguageCustomDisclaimer  -contains $CustomDisclaimer) -and
        ($CurrentState.EndUserSpamNotificationCustomFromAddress -eq $FromAddress) -and
        ($CurrentState.OrganizationBrandingEnabled    -eq $UseOrgBranding)
    )

    if ($Settings.remediate -eq $true) {
        if ($StateIsCorrect) {
            Write-LogMessage -API 'Standards' -tenant $Tenant -message 'Global Quarantine Settings are already configured correctly.' -sev Info
        } else {
            try {
                $Params = @{
                    MultiLanguageSetting                     = $ExistingLanguages
                    MultiLanguageSenderName                  = $SenderNames
                    ESNCustomSubject                         = $Subjects
                    MultiLanguageCustomDisclaimer            = $Disclaimers
                    EndUserSpamNotificationCustomFromAddress = $FromAddress
                    OrganizationBrandingEnabled              = $UseOrgBranding
                }

                if ($CurrentState.Name -eq 'DefaultGlobalPolicy') {
                    $Params['Name']                 = 'DefaultGlobalTag'
                    $Params['QuarantinePolicyType'] = 'GlobalQuarantinePolicy'
                    $null = New-ExoRequest -tenantid $Tenant -cmdlet 'New-QuarantinePolicy' -cmdParams $Params
                } else {
                    $Params['Identity'] = $CurrentState.Identity
                    $null = New-ExoRequest -tenantid $Tenant -cmdlet 'Set-QuarantinePolicy' -cmdParams $Params
                }

                Write-LogMessage -API 'Standards' -tenant $Tenant -message 'Successfully configured Global Quarantine Settings.' -sev Info
            } catch {
                $ErrorMessage = Get-CippException -Exception $_
                Write-LogMessage -API 'Standards' -tenant $Tenant -message "Failed to configure Global Quarantine Settings. Error: $($ErrorMessage.NormalizedError)" -sev Error -LogData $ErrorMessage
            }
        }
    }

    if ($Settings.alert -eq $true) {
        if ($StateIsCorrect) {
            Write-LogMessage -API 'Standards' -tenant $Tenant -message 'Global Quarantine Settings are configured correctly.' -sev Info
        } else {
            Write-StandardsAlert -message 'Global Quarantine Settings do not match the desired configuration.' -object $CurrentState -tenant $Tenant -standardName 'GlobalQuarantineSettings' -standardId $Settings.standardId
            Write-LogMessage -API 'Standards' -tenant $Tenant -message 'Global Quarantine Settings do not match the desired configuration.' -sev Info
        }
    }

    if ($Settings.report -eq $true) {
        $CurrentValue = @{
            MultiLanguageSenderName                  = $CurrentState.MultiLanguageSenderName
            ESNCustomSubject                         = $CurrentState.ESNCustomSubject
            MultiLanguageCustomDisclaimer            = $CurrentState.MultiLanguageCustomDisclaimer
            EndUserSpamNotificationCustomFromAddress = $CurrentState.EndUserSpamNotificationCustomFromAddress
            OrganizationBrandingEnabled              = $CurrentState.OrganizationBrandingEnabled
        }
        $ExpectedValue = @{
            MultiLanguageSenderName                  = @($SenderName)
            ESNCustomSubject                         = @($CustomSubject)
            MultiLanguageCustomDisclaimer            = @($CustomDisclaimer)
            EndUserSpamNotificationCustomFromAddress = $FromAddress
            OrganizationBrandingEnabled              = $UseOrgBranding
        }

        Set-CIPPStandardsCompareField -FieldName 'standards.GlobalQuarantineSettings' -CurrentValue $CurrentValue -ExpectedValue $ExpectedValue -TenantFilter $Tenant
        Add-CIPPBPAField -FieldName 'GlobalQuarantineSettingsConfigured' -FieldValue $StateIsCorrect -StoreAs bool -Tenant $Tenant
    }
}
