function Invoke-CIPPStandardSpoofWarn {
    <#
    .FUNCTIONALITY
    Internal
    #>
    param($Tenant, $Settings)
    $CurrentInfo = (New-ExoRequest -tenantid $Tenant -cmdlet 'Get-ExternalInOutlook')
    
    If ($Settings.remediate) {
        $status = if ($Settings.enable -and $Settings.disable) {
            Write-LogMessage -API 'Standards' -tenant $tenant -message 'You cannot both enable and disable the Spoof Warnings setting' -sev Error
            Exit
        } elseif ($Settings.state -eq 'enabled' -or $Settings.enable) { $true } else { $false }

        if ($CurrentInfo.Enabled -eq $status) {
            Write-LogMessage -API 'Standards' -tenant $tenant -message "Outlook external spoof warnings are already set to $status." -sev Info
        } else {
            try {
                New-ExoRequest -tenantid $Tenant -cmdlet 'Set-ExternalInOutlook' -cmdParams @{ Enabled = $status; }
                Write-LogMessage -API 'Standards' -tenant $tenant -message "Outlook external spoof warnings set to $status." -sev Info
            } catch {
                Write-LogMessage -API 'Standards' -tenant $tenant -message "Could not set Outlook external spoof warnings to $status. Error: $($_.exception.message)" -sev Error
            }
        }
    }

    if ($Settings.alert) {
        if ($CurrentInfo.Enabled -eq $true) {
            Write-LogMessage -API 'Standards' -tenant $tenant -message 'Outlook external spoof warnings are enabled.' -sev Info
        } else {
            Write-LogMessage -API 'Standards' -tenant $tenant -message 'Outlook external spoof warnings are not enabled.' -sev Alert
        }
    }

    if ($Settings.report) {
        Add-CIPPBPAField -FieldName 'SpoofingWarnings' -FieldValue [bool]$CurrentInfo.Enabled -StoreAs bool -Tenant $tenant
    }
}
