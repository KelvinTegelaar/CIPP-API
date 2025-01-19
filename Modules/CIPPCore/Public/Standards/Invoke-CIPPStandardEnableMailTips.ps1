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
            "lowimpact"
            "CIS"
            "exo_mailtipsenabled"
        ADDEDCOMPONENT
            {"type":"number","name":"standards.EnableMailTips.MailTipsLargeAudienceThreshold","label":"Number of recipients to trigger the large audience MailTip (Default is 25)","placeholder":"Enter a profile name","default":25}
        IMPACT
            Low Impact
        POWERSHELLEQUIVALENT
            Set-OrganizationConfig
        RECOMMENDEDBY
            "CIS"
        UPDATECOMMENTBLOCK
            Run the Tools\Update-StandardsComments.ps1 script to update this comment block
    .LINK
        https://docs.cipp.app/user-documentation/tenant/standards/list-standards/exchange-standards#low-impact
    #>

    param($Tenant, $Settings)
    ##$Rerun -Type Standard -Tenant $Tenant -Settings $Settings 'EnableMailTips'

    $MailTipsState = New-ExoRequest -tenantid $Tenant -cmdlet 'Get-OrganizationConfig' | Select-Object MailTipsAllTipsEnabled, MailTipsExternalRecipientsTipsEnabled, MailTipsGroupMetricsEnabled, MailTipsLargeAudienceThreshold
    $StateIsCorrect = if ($MailTipsState.MailTipsAllTipsEnabled -and $MailTipsState.MailTipsExternalRecipientsTipsEnabled -and $MailTipsState.MailTipsGroupMetricsEnabled -and $MailTipsState.MailTipsLargeAudienceThreshold -eq $Settings.MailTipsLargeAudienceThreshold) { $true } else { $false }

    if ($Settings.remediate -eq $true) {

        if ($StateIsCorrect -eq $true) {
            Write-LogMessage -API 'Standards' -tenant $Tenant -message 'All MailTips are already enabled.' -sev Info
        } else {
            try {
                New-ExoRequest -useSystemMailbox $true -tenantid $Tenant -cmdlet 'Set-OrganizationConfig' -cmdparams @{ MailTipsAllTipsEnabled = $true; MailTipsExternalRecipientsTipsEnabled = $true; MailTipsGroupMetricsEnabled = $true; MailTipsLargeAudienceThreshold = $Settings.MailTipsLargeAudienceThreshold }
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
            Write-LogMessage -API 'Standards' -tenant $Tenant -message 'Not all MailTips are enabled' -sev Alert
        }
    }

    if ($Settings.report -eq $true) {

        Add-CIPPBPAField -FieldName 'MailTipsEnabled' -FieldValue $StateIsCorrect -StoreAs bool -Tenant $tenant
    }

}
