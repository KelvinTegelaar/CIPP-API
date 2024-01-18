function Invoke-CIPPStandardEnableMailTips {
    <#
    .FUNCTIONALITY
    Internal
    #>

    param($Tenant, $Settings)

    if ($Settings.remediate) {
        

        try {
            New-ExoRequest -tenantid $Tenant -cmdlet 'Set-OrganizationConfig' -cmdparams @{ MailTipsAllTipsEnabled = $true; MailTipsExternalRecipientsTipsEnabled = $true; MailTipsGroupMetricsEnabled = $true; MailTipsLargeAudienceThreshold = $Settings.MailTipsLargeAudienceThreshold }
            Write-LogMessage -API 'Standards' -tenant $Tenant -message 'Enabled all MailTips' -sev Info
        } catch {
            Write-LogMessage -API 'Standards' -tenant $Tenant -message "Failed to enable all MailTips: $($_.exception.message)" -sev Error
        }
    }


    if ($Settings.alert -or $Settings.report) {
        $MailTipsState = New-ExoRequest -tenantid $Tenant -cmdlet 'Get-OrganizationConfig' | Select-Object MailTipsAllTipsEnabled, MailTipsExternalRecipientsTipsEnabled, MailTipsGroupMetricsEnabled, MailTipsLargeAudienceThreshold
    
        if ($Settings.alert) {
            if ($MailTipsState.MailTipsAllTipsEnabled -and $MailTipsState.MailTipsExternalRecipientsTipsEnabled -and $MailTipsState.MailTipsGroupMetricsEnabled -and $MailTipsState.MailTipsLargeAudienceThreshold -eq $Settings.MailTipsLargeAudienceThreshold) {
                Write-LogMessage -API 'Standards' -tenant $Tenant -message 'All MailTips are enabled' -sev Info
            } else {
                Write-LogMessage -API 'Standards' -tenant $Tenant -message 'Not all MailTips are enabled' -sev Alert
            }
        }

        if ($Settings.report) {

            if ($MailTipsState.MailTipsAllTipsEnabled -and $MailTipsState.MailTipsExternalRecipientsTipsEnabled -and $MailTipsState.MailTipsGroupMetricsEnabled -and $MailTipsState.MailTipsLargeAudienceThreshold -eq $Settings.MailTipsLargeAudienceThreshold) {
                $MailTipsState = $true
            } else {
                $MailTipsState = $false
            }
            Add-CIPPBPAField -FieldName 'MailTipsEnabled' -FieldValue [bool]$MailTipsState -StoreAs bool -Tenant $tenant
        }
    }
}