function Invoke-CIPPStandardEnableMailTips {
    <#
    .FUNCTIONALITY
        Internal
    .COMPONENT
        (APIName) EnableMailTips
    .SYNOPSIS
        (Label) Enable all MailTips
    .DESCRIPTION
        (Helptext) Enables all MailTips in Outlook. MailTips are the notifications Outlook and Outlook on the web shows when an email you create, meets some requirements
        (DocsDescription) Enables all MailTips in Outlook. MailTips are the notifications Outlook and Outlook on the web shows when an email you create, meets some requirements
    .NOTES
        CAT
            Exchange Standards
        TAG
            "CIS M365 5.0 (6.5.2)"
            "exo_mailtipsenabled"
        EXECUTIVETEXT
            Enables helpful notifications in Outlook that warn users about potential email issues, such as sending to large groups, external recipients, or invalid addresses. This reduces email mistakes and improves communication efficiency by providing real-time guidance to employees.
        ADDEDCOMPONENT
            {"type":"number","name":"standards.EnableMailTips.MailTipsLargeAudienceThreshold","label":"Number of recipients to trigger the large audience MailTip (Default is 25)","placeholder":"Enter a profile name","defaultValue":25}
        IMPACT
            Low Impact
        ADDEDDATE
            2024-01-14
        POWERSHELLEQUIVALENT
            Set-OrganizationConfig
        RECOMMENDEDBY
            "CIS"
            "CIPP"
        UPDATECOMMENTBLOCK
            Run the Tools\Update-StandardsComments.ps1 script to update this comment block
    .LINK
        https://docs.cipp.app/user-documentation/tenant/standards/list-standards
    #>

    param($Tenant, $Settings)
    $TestResult = Test-CIPPStandardLicense -StandardName 'EnableMailTips' -TenantFilter $Tenant -RequiredCapabilities @('EXCHANGE_S_STANDARD', 'EXCHANGE_S_ENTERPRISE', 'EXCHANGE_S_STANDARD_GOV', 'EXCHANGE_S_ENTERPRISE_GOV', 'EXCHANGE_LITE') #No Foundation because that does not allow powershell access

    if ($TestResult -eq $false) {
        return $true
    } #we're done.

    try {
        $MailTipsState = New-ExoRequest -tenantid $Tenant -cmdlet 'Get-OrganizationConfig' | Select-Object MailTipsAllTipsEnabled, MailTipsExternalRecipientsTipsEnabled, MailTipsGroupMetricsEnabled, MailTipsLargeAudienceThreshold
    } catch {
        $ErrorMessage = Get-NormalizedError -Message $_.Exception.Message
        Write-LogMessage -API 'Standards' -Tenant $Tenant -Message "Could not get the EnableMailTips state for $Tenant. Error: $ErrorMessage" -Sev Error
        return
    }
    $StateIsCorrect = if ($MailTipsState.MailTipsAllTipsEnabled -and $MailTipsState.MailTipsExternalRecipientsTipsEnabled -and $MailTipsState.MailTipsGroupMetricsEnabled -and $MailTipsState.MailTipsLargeAudienceThreshold -eq $Settings.MailTipsLargeAudienceThreshold) { $true } else { $false }

    if ($Settings.remediate -eq $true) {

        if ($StateIsCorrect -eq $true) {
            Write-LogMessage -API 'Standards' -tenant $Tenant -message 'All MailTips are already enabled.' -sev Info
        } else {
            try {
                New-ExoRequest -useSystemMailbox $true -tenantid $Tenant -cmdlet 'Set-OrganizationConfig' -cmdParams @{ MailTipsAllTipsEnabled = $true; MailTipsExternalRecipientsTipsEnabled = $true; MailTipsGroupMetricsEnabled = $true; MailTipsLargeAudienceThreshold = $Settings.MailTipsLargeAudienceThreshold }
                Write-LogMessage -API 'Standards' -tenant $Tenant -message 'Enabled all MailTips' -sev Info
            } catch {
                $ErrorMessage = Get-NormalizedError -Message $_.Exception.Message
                Write-LogMessage -API 'Standards' -tenant $Tenant -message "Failed to enable all MailTips. Error: $ErrorMessage" -sev Error
            }
        }
    }

    if ($Settings.alert -eq $true) {

        if ($StateIsCorrect -eq $true) {
            Write-LogMessage -API 'Standards' -tenant $Tenant -message 'All MailTips are enabled' -sev Info
        } else {
            Write-StandardsAlert -message 'Not all MailTips are enabled' -object $MailTipsState -tenant $Tenant -standardName 'EnableMailTips' -standardId $Settings.standardId
            Write-LogMessage -API 'Standards' -tenant $Tenant -message 'Not all MailTips are enabled' -sev Info
        }
    }

    if ($Settings.report -eq $true) {
        $CurrentValue = $MailTipsState
        $ExpectedValue = [PSCustomObject]@{
            MailTipsAllTipsEnabled                = $true
            MailTipsExternalRecipientsTipsEnabled = $true
            MailTipsGroupMetricsEnabled           = $true
            MailTipsLargeAudienceThreshold        = $Settings.MailTipsLargeAudienceThreshold
        }

        Set-CIPPStandardsCompareField -FieldName 'standards.EnableMailTips' -CurrentValue $CurrentValue -ExpectedValue $ExpectedValue -Tenant $tenant
        Add-CIPPBPAField -FieldName 'MailTipsEnabled' -FieldValue $StateIsCorrect -StoreAs bool -Tenant $tenant
    }

}
