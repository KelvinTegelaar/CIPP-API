function Invoke-CIPPStandardBranding {
    <#
    .FUNCTIONALITY
        Internal
    .COMPONENT
        (APIName) Branding
    .SYNOPSIS
        (Label) Set branding for the tenant
    .DESCRIPTION
        (Helptext) Sets the branding for the tenant. This includes the login page, and the Office 365 portal.
        (DocsDescription) Sets the branding for the tenant. This includes the login page, and the Office 365 portal.
    .NOTES
        CAT
            Global Standards
        TAG
        EXECUTIVETEXT
            Customizes Microsoft 365 login pages and portals with company branding, including logos, colors, and messaging. This creates a consistent corporate identity experience for employees and reinforces brand recognition while maintaining professional appearance across all Microsoft services.
        ADDEDCOMPONENT
            {"type":"textField","name":"standards.Branding.signInPageText","label":"Sign-in page text","required":false}
            {"type":"textField","name":"standards.Branding.usernameHintText","label":"Username hint Text","required":false}
            {"type":"switch","name":"standards.Branding.hideAccountResetCredentials","label":"Hide self-service password reset"}
            {"type":"autoComplete","multiple":false,"label":"Visual Template","name":"standards.Branding.layoutTemplateType","options":[{"label":"Full-screen background","value":"default"},{"label":"Partial-screen background","value":"verticalSplit"}]}
            {"type":"switch","name":"standards.Branding.isHeaderShown","label":"Show header"}
            {"type":"switch","name":"standards.Branding.isFooterShown","label":"Show footer"}
        IMPACT
            Low Impact
        ADDEDDATE
            2024-05-13
        POWERSHELLEQUIVALENT
            Portal only
        RECOMMENDEDBY
        REQUIREDCAPABILITIES
            "AAD_PREMIUM"
            "AAD_PREMIUM_P2"
            "OFFICE_BUSINESS"
        UPDATECOMMENTBLOCK
            Run the Tools\Update-StandardsComments.ps1 script to update this comment block
    .LINK
        https://docs.cipp.app/user-documentation/tenant/standards/alignment/templates/available-standards
    #>

    param($Tenant, $Settings)

    $TestResult = Test-CIPPStandardLicense -StandardName 'Branding' -TenantFilter $Tenant -Preset Entra -RequiredCapabilities @('OFFICE_BUSINESS')

    if ($TestResult -eq $false) {
        return $true
    } #we're done.

    ##$Rerun -Type Standard -Tenant $Tenant -Settings $Settings 'Branding'

    $TenantId = Get-Tenants -TenantFilter $Tenant

    $Localizations = New-GraphGetRequest -Uri "https://graph.microsoft.com/beta/organization/$($TenantId.customerId)/branding/localizations" -tenantID $Tenant -AsApp $true
    # Get layoutTemplateType value using null-coalescing operator
    $layoutTemplateType = $Settings.layoutTemplateType.value ?? $Settings.layoutTemplateType

    $SetSignInPageText = -not [string]::IsNullOrEmpty($Settings.signInPageText)
    $SetUsernameHintText = -not [string]::IsNullOrEmpty($Settings.usernameHintText)

    $BrandingBody = [ordered]@{
        loginPageTextVisibilitySettings = [pscustomobject]@{
            hideAccountResetCredentials = $Settings.hideAccountResetCredentials
        }
        loginPageLayoutConfiguration    = [pscustomobject]@{
            layoutTemplateType = $layoutTemplateType
            isHeaderShown      = $Settings.isHeaderShown
            isFooterShown      = $Settings.isFooterShown
        }
    }
    if ($SetSignInPageText) { $BrandingBody['signInPageText'] = $Settings.signInPageText }
    if ($SetUsernameHintText) { $BrandingBody['usernameHintText'] = $Settings.usernameHintText }
    # If default localization (id "0") exists, use that to get the currentState. Otherwise we have to create it first.
    if ($Localizations | Where-Object { $_.id -eq '0' }) {
        try {
            $CurrentState = New-GraphGetRequest -Uri "https://graph.microsoft.com/beta/organization/$($TenantId.customerId)/branding/localizations/0" -tenantID $Tenant -AsApp $true
        } catch {
            $ErrorMessage = Get-CippException -Exception $_
            Write-LogMessage -API 'Standards' -Tenant $Tenant -Message "Could not get the Branding state for $Tenant. Error: $($ErrorMessage.NormalizedError)" -Sev Error -LogData $ErrorMessage
            return
        }
    } else {
        try {
            $GraphRequest = @{
                tenantID    = $Tenant
                uri         = "https://graph.microsoft.com/beta/organization/$($TenantId.customerId)/branding/localizations"
                AsApp       = $true
                Type        = 'POST'
                ContentType = 'application/json; charset=utf-8'
                Body        = [pscustomobject]$BrandingBody | ConvertTo-Json -Compress
            }
            $CurrentState = New-GraphPostRequest @GraphRequest
        } catch {
            $ErrorMessage = Get-CippException -Exception $_
            Write-LogMessage -API 'Standards' -Tenant $Tenant -Message "Could not create the default Branding localization for $Tenant. Error: $($ErrorMessage.NormalizedError)" -Sev Error -LogData $ErrorMessage
            return
        }
    }

    $StateIsCorrect = ($CurrentState.loginPageTextVisibilitySettings.hideAccountResetCredentials -eq $Settings.hideAccountResetCredentials) -and
    ($CurrentState.loginPageLayoutConfiguration.layoutTemplateType -eq $layoutTemplateType) -and
    ($CurrentState.loginPageLayoutConfiguration.isHeaderShown -eq $Settings.isHeaderShown) -and
    ($CurrentState.loginPageLayoutConfiguration.isFooterShown -eq $Settings.isFooterShown) -and
    (-not $SetSignInPageText -or ($CurrentState.signInPageText -eq $Settings.signInPageText)) -and
    (-not $SetUsernameHintText -or ($CurrentState.usernameHintText -eq $Settings.usernameHintText))

    $CurrentValue = [ordered]@{
        loginPageTextVisibilitySettings = $CurrentState.loginPageTextVisibilitySettings | Select-Object -Property hideAccountResetCredentials
        loginPageLayoutConfiguration    = $CurrentState.loginPageLayoutConfiguration | Select-Object -Property layoutTemplateType, isHeaderShown, isFooterShown
    }
    $ExpectedValue = [ordered]@{
        loginPageTextVisibilitySettings = [pscustomobject]@{
            hideAccountResetCredentials = $Settings.hideAccountResetCredentials
        }
        loginPageLayoutConfiguration    = [pscustomobject]@{
            layoutTemplateType = $layoutTemplateType
            isHeaderShown      = $Settings.isHeaderShown
            isFooterShown      = $Settings.isFooterShown
        }
    }
    if ($SetSignInPageText) {
        $CurrentValue['signInPageText'] = $CurrentState.signInPageText
        $ExpectedValue['signInPageText'] = $Settings.signInPageText
    }
    if ($SetUsernameHintText) {
        $CurrentValue['usernameHintText'] = $CurrentState.usernameHintText
        $ExpectedValue['usernameHintText'] = $Settings.usernameHintText
    }
    $CurrentValue = [pscustomobject]$CurrentValue
    $ExpectedValue = [pscustomobject]$ExpectedValue

    if ($Settings.remediate -eq $true) {
        if ($StateIsCorrect -eq $true) {
            Write-LogMessage -API 'Standards' -Tenant $Tenant -Message 'Branding is already applied correctly.' -Sev Info
        } else {
            try {
                $GraphRequest = @{
                    tenantID    = $Tenant
                    uri         = "https://graph.microsoft.com/beta/organization/$($TenantId.customerId)/branding/localizations/0"
                    AsApp       = $true
                    Type        = 'PATCH'
                    ContentType = 'application/json; charset=utf-8'
                    Body        = [pscustomobject]$BrandingBody | ConvertTo-Json -Compress
                }
                $null = New-GraphPostRequest @GraphRequest
                Write-LogMessage -API 'Standards' -Tenant $Tenant -Message 'Successfully updated branding.' -Sev Info
            } catch {
                $ErrorMessage = Get-CippException -Exception $_
                Write-LogMessage -API 'Standards' -Tenant $Tenant -Message "Failed to update branding. Error: $($ErrorMessage.NormalizedError)" -Sev Error -LogData $ErrorMessage
            }
        }

    }

    if ($Settings.alert -eq $true) {

        if ($StateIsCorrect -eq $true) {
            Write-LogMessage -API 'Standards' -Tenant $Tenant -Message 'Branding is correctly set.' -Sev Info
        } else {
            Write-StandardsAlert -message 'Branding is incorrectly set.' -object ($CurrentState | Select-Object -Property signInPageText, usernameHintText, loginPageTextVisibilitySettings, loginPageLayoutConfiguration) -tenant $Tenant -standardName 'Branding' -standardId $Settings.standardId
            Write-LogMessage -API 'Standards' -Tenant $Tenant -Message 'Branding is incorrectly set.' -Sev Info
        }
    }

    if ($Settings.report -eq $true) {
        Set-CIPPStandardsCompareField -FieldName 'standards.Branding' -CurrentValue $CurrentValue -ExpectedValue $ExpectedValue -TenantFilter $Tenant
        Add-CIPPBPAField -FieldName 'Branding' -FieldValue [bool]$StateIsCorrect -StoreAs bool -Tenant $Tenant
    }
}
