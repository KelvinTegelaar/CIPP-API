function Invoke-CIPPStandardPhishProtection {
    <#
    .FUNCTIONALITY
    Internal
    #>
    param($Tenant, $Settings)
    If ($Settings.remediate) {
        
        $TenantId = Get-Tenants | Where-Object -Property defaultDomainName -EQ $tenant 
        try {
            $currentBody = (New-GraphGetRequest -Uri "https://graph.microsoft.com/beta/organization/$($TenantId.customerId)/branding/localizations/0/customCSS" -tenantid $tenant)
        } catch {
            Write-LogMessage -API 'Standards' -tenant $tenant -message "Could not get the branding for $($Tenant). This tenant might not have premium licenses available: $($_.Exception.Message)" -sev Error
        }
        $CSS = @"
.ext-sign-in-box {
    background-image: url(https://$($Settings.URL)/api/PublicPhishingCheck?Tenantid=$($tenant));
}
"@
        try {
            if ($currentBody -like "*$CSS*") {
                Write-Host 'Logon Screen Phising Protection system already active'
                Write-LogMessage -API 'Standards' -tenant $tenant -message 'Logon Screen Phishing Protection system already active' -sev Info
            } else {
                $currentBody = $currentBody + $CSS
                Write-Host 'Creating Logon Screen Phising Protection System'
                New-GraphPostRequest -tenantid $tenant -Uri "https://graph.microsoft.com/beta/organization/$($TenantId.customerId)/branding/localizations/0/customCSS" -ContentType 'text/css' -asApp $true -Type PUT -Body $CSS
                Write-LogMessage -API 'Standards' -tenant $tenant -message 'Enabled Logon Screen Phishing Protection system' -sev Info
            }
        } catch {
            Write-LogMessage -API 'Standards' -tenant $tenant -message "Could not set Logon Screen Phishing Protection System for $($Tenant): $($_.Exception.Message)" -sev Error
        }
    }
}