function Invoke-CIPPBaselinePhishProtection {
    <#
    .SYNOPSIS
        PhishProtection executor: appends the phishing-check CSS to the sign-in branding.
    .DESCRIPTION
        The classic's write, verbatim: strip a known malformed variant of the canary CSS
        (empty URL parameter) first, create the default branding localization when the
        tenant has none (Accept-Language 0 header, tolerating the already-exists conflict),
        then PUT the current CSS with the canary appended - never a blind overwrite of an
        operator's existing custom CSS.
    .FUNCTIONALITY
        Internal
    #>
    [CmdletBinding()]
    param(
        $Remediate,
        $TenantFilter,
        $Current
    )

    $CurrentBody = "$($Current.currentBody)"
    $CSS = "$($Current.expectedCss)"
    $CustomerId = "$($Current.customerId)"
    if ([string]::IsNullOrWhiteSpace($CustomerId)) { throw 'No tenant customer id was carried from the prepare hook - refusing a blind write.' }

    $MalformedCSSPattern = '\.ext-sign-in-box\s*\{\s*background-image:\s*url\(https://clone\.cipp\.app/api/PublicPhishingCheck\?Tenantid=[^&]*&URL=\);\s*\}'
    if ($CurrentBody -match $MalformedCSSPattern) {
        Write-LogMessage -API 'Baselines' -tenant $TenantFilter -message 'Removing a malformed PhishProtection CSS block before rewriting.' -Sev 'Info'
        $CurrentBody = $CurrentBody -replace $MalformedCSSPattern, ''
    }

    if ([string]::IsNullOrWhiteSpace($CurrentBody)) {
        # No CSS usually means no default localization either - create it, tolerating the
        # object-conflict answer when it already exists.
        $DefaultLocalizationExists = $false
        try {
            $Localizations = New-GraphGetRequest -uri "https://graph.microsoft.com/beta/organization/$CustomerId/branding/localizations" -tenantid $TenantFilter -AsApp $true
            $DefaultLocalizationExists = [bool]($Localizations | Where-Object { "$($_.id)" -eq '0' })
        } catch {
            Write-LogMessage -API 'Baselines' -tenant $TenantFilter -message "Could not check for the default branding localization - creation will be attempted: $($_.Exception.Message)" -Sev 'Warning'
        }
        if (-not $DefaultLocalizationExists) {
            $DefaultBrandingBody = '{"usernameHintText":null,"signInPageText":null,"backgroundColor":null,"customPrivacyAndCookiesText":null,"customCannotAccessYourAccountText":null,"customForgotMyPasswordText":null,"customTermsOfUseText":null,"loginPageLayoutConfiguration":{"layoutTemplateType":"default","isFooterShown":true,"isHeaderShown":false},"loginPageTextVisibilitySettings":{"hideAccountResetCredentials":false,"hideTermsOfUse":true,"hidePrivacyAndCookies":true},"contentCustomization":{"conditionalAccess":[],"attributeCollection":[]}}'
            try {
                $null = New-GraphPostRequest -tenantid $TenantFilter -uri "https://graph.microsoft.com/beta/organization/$CustomerId/branding/localizations/" -ContentType 'application/json' -AsApp $true -type POST -body $DefaultBrandingBody -AddedHeaders @{ 'Accept-Language' = 0 }
            } catch {
                $GraphError = $null
                try { $GraphError = (Get-CippException -Exception $_).RawError | ConvertFrom-Json -ErrorAction Stop } catch {}
                $IsConflict = ($GraphError.error.code -eq 'Request_BadRequest') -and [bool]($GraphError.error.details | Where-Object { $_.code -eq 'ObjectConflict' -and $_.target -eq 'id' })
                if ($IsConflict) {
                    Write-LogMessage -API 'Baselines' -tenant $TenantFilter -message 'The default branding localization already exists - continuing with it.' -Sev 'Info'
                } else {
                    throw
                }
            }
        }
    }

    if ($CurrentBody -like "*$CSS*") {
        Write-LogMessage -API 'Baselines' -tenant $TenantFilter -message 'The logon screen phishing protection CSS is already active.' -Sev 'Info'
        return
    }
    $CurrentBody = $CurrentBody + $CSS
    New-GraphPostRequest -tenantid $TenantFilter -uri "https://graph.microsoft.com/beta/organization/$CustomerId/branding/localizations/0/customCSS" -ContentType 'text/css' -AsApp $true -type PUT -body $CurrentBody
    Write-LogMessage -API 'Baselines' -tenant $TenantFilter -message 'Enabled the logon screen phishing protection CSS.' -Sev 'Info'
}
