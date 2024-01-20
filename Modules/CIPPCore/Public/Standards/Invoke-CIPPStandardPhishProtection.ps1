function Invoke-CIPPStandardPhishProtection {
    <#
    .FUNCTIONALITY
    Internal
    #>
    param($Tenant, $Settings)
    $TenantId = Get-Tenants | Where-Object -Property defaultDomainName -EQ $tenant 

    try {
        $currentBody = (New-GraphGetRequest -Uri "https://graph.microsoft.com/beta/organization/$($TenantId.customerId)/branding/localizations/0/customCSS" -tenantid $tenant)
    } catch {
        Write-LogMessage -API 'Standards' -tenant $tenant -message "Could not get the branding for $($Tenant). This tenant might not have premium licenses available: $($_.Exception.Message)" -sev Error
    }
    $CSS = @"
.ext-sign-in-box {
    background-image: url($($Settings.URL)/api/PublicPhishingCheck?Tenantid=$($tenant));
}
"@
    If ($Settings.remediate) {
        
        try {
            if (!$currentBody) {
                $AddedHeaders = @{'Accept-Language' = 0}
                $defaultBrandingBody = '{"usernameHintText":null,"signInPageText":null,"backgroundColor":null,"customPrivacyAndCookiesText":null,"customCannotAccessYourAccountText":null,"customForgotMyPasswordText":null,"customTermsOfUseText":null,"loginPageLayoutConfiguration":{"layoutTemplateType":"default","isFooterShown":true,"isHeaderShown":false},"loginPageTextVisibilitySettings":{"hideAccountResetCredentials":false,"hideTermsOfUse":true,"hidePrivacyAndCookies":true},"contentCustomization":{"conditionalAccess":[],"attributeCollection":[]}}'
                New-GraphPostRequest -tenantid $tenant -Uri "https://graph.microsoft.com/beta/organization/$($TenantId.customerId)/branding/localizations/" -ContentType 'application/json' -asApp $true -Type POST -Body $defaultBrandingBody -AddedHeaders $AddedHeaders
            }
            if ($currentBody -like "*$CSS*") {
                Write-Host 'Logon Screen Phishing Protection system already active'
                Write-LogMessage -API 'Standards' -tenant $tenant -message 'Logon Screen Phishing Protection system already active' -sev Info
            } else {
                $currentBody = $currentBody + $CSS
                Write-Host 'Creating Logon Screen Phishing Protection System'
                New-GraphPostRequest -tenantid $tenant -Uri "https://graph.microsoft.com/beta/organization/$($TenantId.customerId)/branding/localizations/0/customCSS" -ContentType 'text/css' -asApp $true -Type PUT -Body $CSS
                Write-LogMessage -API 'Standards' -tenant $tenant -message 'Enabled Logon Screen Phishing Protection system' -sev Info
            }
        } catch {
            Write-LogMessage -API 'Standards' -tenant $tenant -message "Could not set Logon Screen Phishing Protection System for $($Tenant): $($_.Exception.Message)" -sev Error
        }
    }

    if ($Settings.alert) {
        if ($currentBody -like "*$CSS*") {
            Write-LogMessage -API 'Standards' -tenant $tenant -message 'PhishProtection is enabled.' -sev Info
        } else {
            Write-LogMessage -API 'Standards' -tenant $tenant -message 'PhishProtection is not enabled.' -sev Alert
        }
    }
    if ($Settings.report) {
        if ($currentBody -like "*$CSS*") { $authstate = $true } else { $authstate = $false }
        Add-CIPPBPAField -FieldName 'PhishProtection' -FieldValue [bool]$authstate -StoreAs bool -Tenant $tenant
    }
}
