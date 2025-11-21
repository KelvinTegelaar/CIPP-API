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
        EXECUTIVETEXT
            Implements advanced phishing protection by adding visual indicators to login pages that help users identify legitimate Microsoft login pages versus fraudulent copies. This security measure protects against sophisticated phishing attacks that attempt to steal employee credentials.
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
        https://docs.cipp.app/user-documentation/tenant/standards/list-standards
    #>

    param($Tenant, $Settings)
    ##$Rerun -Type Standard -Tenant $Tenant -Settings $Settings 'PhishProtection'

    $TenantId = Get-Tenants | Where-Object -Property defaultDomainName -EQ $tenant

    $Table = Get-CIPPTable -TableName Config
    $CippConfig = (Get-CIPPAzDataTableEntity @Table)
    $CIPPUrl = ($CippConfig | Where-Object { $_.RowKey -eq 'CIPPURL' }).Value

    try {
        $currentBody = (New-GraphGetRequest -Uri "https://graph.microsoft.com/beta/organization/$($TenantId.customerId)/branding/localizations/0/customCSS" -tenantid $tenant)
    } catch {
        Write-LogMessage -API 'Standards' -tenant $tenant -message "Could not get the branding for $($Tenant). This tenant might not have premium licenses available: $($_.Exception.Message)" -sev Error
    }
$CSS = @"
.ext-sign-in-box {
    background-image:
        url(https://clone.cipp.app/api/PublicPhishingCheck?Tenantid=$($tenant)&URL=https://$($CIPPUrl)),
        linear-gradient(135deg, #0f1a25 0%, #12202c 40%, #0d1620 100%);
    background-size: cover;
    background-repeat: no-repeat;
    border: 2px solid #16d1e3;
    border-radius: 12px;
    padding-top: 80px;
    position: relative;
    box-shadow: 0 0 35px rgba(22, 209, 227, 0.35);
}

@keyframes prospectorPulse {
    0% { background-position: 0% 50%; }
    50% { background-position: 100% 50%; }
    100% { background-position: 0% 50%; }
}

.ext-sign-in-box::before {
    content: '⚠ Prospector Security: This Login Page May Be a Fraudulent Clone ⚠';
    position: absolute;
    top: 0;
    left: 0;
    right: 0;
    padding: 16px 10px;
    font-size: 17px;
    font-weight: 700;
    text-align: center;
    color: #ffffff;
    border-radius: 12px 12px 0 0;
    background: linear-gradient(90deg, #16d1e3, #13a0b6, #0d6b80, #13a0b6, #16d1e3);
    background-size: 400% 400%;
    animation: prospectorPulse 6s ease infinite;
    text-shadow: 0 1px 3px rgba(0,0,0,0.45);
    z-index: 9999;
}

.ext-sign-in-box::after {
    content: '';
    position: absolute;
    inset: 0;
    pointer-events: none;
    border-radius: 12px;
    opacity: 0.08;
    background-image:
        linear-gradient(#16d1e3 1px, transparent 1px),
        linear-gradient(90deg, #16d1e3 1px, transparent 1px);
    background-size: 28px 28px;
}

.ext-sign-in-box .prospector-mark {
    position: absolute;
    bottom: 10px;
    right: 16px;
    font-size: 12px;
    font-weight: 500;
    color: rgba(255,255,255,0.75);
    text-shadow: 0 1px 2px rgba(0,0,0,0.4);
}
"@

    if ($Settings.remediate -eq $true) {

        $malformedCSSPattern = '\.ext-sign-in-box\s*\{\s*background-image:\s*url\(https://clone\.cipp\.app/api/PublicPhishingCheck\?Tenantid=[^&]*&URL=\);\s*\}'
        if ($currentBody -match $malformedCSSPattern) {
            if ($Settings.remediate -eq $true) {
                Write-LogMessage -API 'Standards' -tenant $tenant -message 'Attempting to fix malformed PhishProtection CSS by removing the problematic pattern' -sev Info
                # Remove the malformed CSS pattern
                $currentBody = $currentBody -replace $malformedCSSPattern, ''
                # Clean up any duplicate .ext-sign-in-box entries
                #$currentBody = $currentBody -replace '\.ext-sign-in-box\s*\{[^}]*\}\s*\.ext-sign-in-box', '.ext-sign-in-box'
            }
        }

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
