function Invoke-CIPPStandardEnableExchangeOnlineModernAuth {
    <#
    .FUNCTIONALITY
    Internal
    #>

    param($Tenant, $Settings)
    $ModernAuthState = New-ExoRequest -tenantid $Tenant -cmdlet 'Get-OrganizationConfig' | 
        Select-Object OAuth2ClientProfileEnabled
    
    $StateIsCorrect = if (
        $ModernAuthState.OAuth2ClientProfileEnabled -eq $true
    ) { $true } else { $false }

    if ($Settings.remediate) {
        
        if ($StateIsCorrect) {
            Write-LogMessage -API 'Standards' -tenant $Tenant -message 'Modern authentication for Exchange Online is already enabled.' -sev Info
        } else {
            $cmdparams = @{
                OAuth2ClientProfileEnabled = $true
            }

            try {
                New-ExoRequest -tenantid $Tenant -cmdlet 'Set-OrganizationConfig' -cmdparams $cmdparams
                Write-LogMessage -API 'Standards' -tenant $Tenant -message 'Enabled Modern authentication for Exchange Online' -sev Info
            } catch {
                Write-LogMessage -API 'Standards' -tenant $Tenant -message "Failed to enable Modern authentication for Exchange Online. Error: $($_.exception.message)" -sev Error
            }
        }
    }

    if ($Settings.alert) {

        if ($StateIsCorrect) {
            Write-LogMessage -API 'Standards' -tenant $Tenant -message 'Enabled Modern authentication for Exchange Online' -sev Info
        } else {
            Write-LogMessage -API 'Standards' -tenant $Tenant -message 'Modern authentication for Exchange Online is not enabled' -sev Alert
        }
    }

    if ($Settings.report) {

        Add-CIPPBPAField -FieldName 'ExchangeOnlineModernAuth' -FieldValue [bool]$StateIsCorrect -StoreAs bool -Tenant $tenant
    }
    
}