function Invoke-CIPPStandardEnableCustomerLockbox {
    <#
    .FUNCTIONALITY
    Internal
    #>
    param($Tenant, $Settings)
    
    $CustomerLockboxStatus = (New-ExoRequest -tenantid $Tenant -cmdlet 'Get-OrganizationConfig').CustomerLockboxEnabled
    if ($Settings.remediate) {
        try {

            if ($CustomerLockboxStatus) {
                Write-LogMessage -API 'Standards' -tenant $tenant -message 'Customer Lockbox already enabled' -sev Info
            } else {
                New-ExoRequest -tenantid $Tenant -cmdlet 'Set-OrganizationConfig' -cmdParams @{ CustomerLockboxEnabled = $true } -UseSystemMailbox $true
                Write-LogMessage -API 'Standards' -tenant $tenant -message 'Successfully enabled Customer Lockbox' -sev Info
            }
        } catch [System.Management.Automation.RuntimeException] {
            Write-LogMessage -API 'Standards' -tenant $tenant -message 'Failed to enable Customer Lockbox. E5 license required' -sev Error
        } catch {
            Write-LogMessage -API 'Standards' -tenant $tenant -message "Failed to enable Customer Lockbox. Error: $($_.Exception.Message)" -sev Error
        }
    }

    if ($Settings.alert) {
        if ($CustomerLockboxStatus) {
            Write-LogMessage -API 'Standards' -tenant $tenant -message 'Customer Lockbox is enabled' -sev Info
        } else {
            Write-LogMessage -API 'Standards' -tenant $tenant -message 'Customer Lockbox is not enabled' -sev Alert
        }
    }

    if ($Settings.report) {
        Add-CIPPBPAField -FieldName 'CustomerLockboxEnabled' -FieldValue [bool]$CustomerLockboxStatus -StoreAs bool -Tenant $tenant
    }
}
