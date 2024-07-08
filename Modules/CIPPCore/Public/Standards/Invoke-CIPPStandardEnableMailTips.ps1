function Invoke-CIPPStandardEnableMailTips {
    <#
    .FUNCTIONALITY
    Internal
    #>

    param($Tenant, $Settings)
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
