function Invoke-CIPPStandardEnableCustomerLockbox {
    <#
    .FUNCTIONALITY
    Internal
    #>
    param($Tenant, $Settings)
    
    if ($Settings.remediate) {
        try {
            New-ExoRequest -tenantid $Tenant -cmdlet 'Set-OrganizationConfig' -cmdParams @{ CustomerLockboxEnabled = $true } -UseSystemMailbox $true
            Write-LogMessage -API 'Standards' -tenant $tenant -message 'Successfully enabled Customer Lockbox' -sev Info
        } catch {
            Write-LogMessage -API 'Standards' -tenant $tenant -message "Failed to enable Customer Lockbox. Error: $($_.exception.message)" -sev Error
        }
    }
    if ($Settings.alert -or $Settings.report) {
        $CurrentInfo = New-ExoRequest -tenantid $Tenant -cmdlet 'Get-OrganizationConfig'

        if ($Settings.alert) {
            if ($CurrentInfo.CustomerLockboxEnabled) {
                Write-LogMessage -API 'Standards' -tenant $tenant -message 'Customer Lockbox is enabled' -sev Info
            } else {
                Write-LogMessage -API 'Standards' -tenant $tenant -message 'Customer Lockbox is not enabled' -sev Alert
            }
        }
        if ($Settings.report) {
            Add-CIPPBPAField -FieldName 'CustomerLockboxEnabled' -FieldValue [bool]$CurrentInfo.CustomerLockboxEnabled -StoreAs bool -Tenant $tenant
        }
    }

}

