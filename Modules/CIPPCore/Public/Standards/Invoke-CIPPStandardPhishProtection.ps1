function Invoke-CIPPStandardPhishProtection {
    <#
    .FUNCTIONALITY
        Internal
    .COMPONENT
        (APIName) PhishProtection
    .SYNOPSIS
        (Label) Enable Phishing Protection system via branding CSS
    .DESCRIPTION
        (Helptext) Adds branding to the logon page that only appears if the url is not login.microsoftonline.com. This potentially prevents AITM attacks via EvilNginx. This will also automatically generate alerts if a clone of your login page has been found when set to Remediate.
        (DocsDescription) Adds branding to the logon page that only appears if the url is not login.microsoftonline.com. This potentially prevents AITM attacks via EvilNginx. This will also automatically generate alerts if a clone of your login page has been found when set to Remediate.
    .NOTES
        CAT
            Global Standards
        TAG
        ADDEDCOMPONENT
        IMPACT
            Low Impact
        ADDEDDATE
            2024-01-22
        DISABLEDFEATURES
            {"report":true,"warn":true,"remediate":false}
        POWERSHELLEQUIVALENT
            Portal only
        RECOMMENDEDBY
            "CIPP"
        UPDATECOMMENTBLOCK
            Run the Tools\Update-StandardsComments.ps1 script to update this comment block
    .LINK
        https://docs.cipp.app/user-documentation/tenant/standards/list-standards/global-standards#low-impact
    #>

    param($Tenant, $Settings)
    ##$Rerun -Type Standard -Tenant $Tenant -Settings $Settings 'PhishProtection'

    $TenantId = Get-Tenants | Where-Object -Property defaultDomainName -EQ $tenant

    try {
        $currentBody = (New-GraphGetRequest -Uri "https://graph.microsoft.com/beta/organization/$($TenantId.customerId)/branding/localizations/0/customCSS" -tenantid $tenant)
    } catch {
        Write-LogMessage -API 'Standards' -tenant $tenant -message "Could not get the branding for $($Tenant). This tenant might not have premium licenses available: $($_.Exception.Message)" -sev Error
    }
    $CSS = @"
.ext-sign-in-box {
    background-image: url(https://clone.cipp.app/api/PublicPhishingCheck?Tenantid=$($tenant)&URL=$($Settings.URL));
}
"@
    if ($Settings.remediate -eq $true) {

        try {
            if (!$currentBody) {
                $AddedHeaders = @{'Accept-Language' = 0 }
                $defaultBrandingBody = '{"usernameHintText":null,"signInPageText":null,"backgroundColor":null,"customPrivacyAndCookiesText":null,"customCannotAccessYourAccountText":null,"customForgotMyPasswordText":null,"customTermsOfUseText":null,"loginPageLayoutConfiguration":{"layoutTemplateType":"default","isFooterShown":true,"isHeaderShown":false},"loginPageTextVisibilitySettings":{"hideAccountResetCredentials":false,"hideTermsOfUse":true,"hidePrivacyAndCookies":true},"contentCustomization":{"conditionalAccess":[],"attributeCollection":[]}}'
                try {
                    New-GraphPostRequest -tenantid $tenant -Uri "https://graph.microsoft.com/beta/organization/$($TenantId.customerId)/branding/localizations/" -ContentType 'application/json' -asApp $true -Type POST -Body $defaultBrandingBody -AddedHeaders $AddedHeaders
                } catch {

                }
            }
            if ($currentBody -like "*$CSS*") {
                Write-Host 'Logon Screen Phishing Protection system already active'
                Write-LogMessage -API 'Standards' -tenant $tenant -message 'Logon Screen Phishing Protection system already active' -sev Info
            } else {
                $currentBody = $currentBody + $CSS
                Write-Host 'Creating Logon Screen Phishing Protection System'
                New-GraphPostRequest -tenantid $tenant -Uri "https://graph.microsoft.com/beta/organization/$($TenantId.customerId)/branding/localizations/0/customCSS" -ContentType 'text/css' -asApp $true -Type PUT -Body $currentBody

                Write-LogMessage -API 'Standards' -tenant $tenant -message 'Enabled Logon Screen Phishing Protection system' -sev Info
            }
        } catch {
            $ErrorMessage = Get-NormalizedError -Message $_.Exception.Message
            Write-LogMessage -API 'Standards' -tenant $tenant -message "Could not set Logon Screen Phishing Protection System for $($Tenant): $ErrorMessage" -sev Error
        }
    }

    if ($Settings.alert -eq $true) {
        if ($currentBody -like "*$CSS*") {
            Write-LogMessage -API 'Standards' -tenant $tenant -message 'PhishProtection is enabled.' -sev Info
        } else {
            Write-StandardsAlert -message 'PhishProtection is not enabled' -object $currentBody -tenant $tenant -standardName 'PhishProtection' -standardId $Settings.standardId
            Write-LogMessage -API 'Standards' -tenant $tenant -message 'PhishProtection is not enabled.' -sev Info
        }
    }
    if ($Settings.report -eq $true) {
        if ($currentBody -like "*$CSS*") { $authState = $true } else { $authState = $false }
        Add-CIPPBPAField -FieldName 'PhishProtection' -FieldValue $authState -StoreAs bool -Tenant $tenant
        Set-CIPPStandardsCompareField -FieldName 'standards.PhishProtection' -FieldValue $authState -Tenant $tenant
    }
}
