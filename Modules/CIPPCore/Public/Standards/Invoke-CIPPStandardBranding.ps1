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
        UPDATECOMMENTBLOCK
            Run the Tools\Update-StandardsComments.ps1 script to update this comment block
    .LINK
        https://docs.cipp.app/user-documentation/tenant/standards/list-standards/global-standards#low-impact
    #>

    param($Tenant, $Settings)
    ##$Rerun -Type Standard -Tenant $Tenant -Settings $Settings 'Branding'

    $TenantId = Get-Tenants | Where-Object -Property defaultDomainName -EQ $Tenant

    try {
        $CurrentState = New-GraphGetRequest -Uri "https://graph.microsoft.com/beta/organization/$($TenantId.customerId)/branding/localizations/0" -tenantID $Tenant -AsApp $true
    } catch {
        $ErrorMessage = Get-NormalizedError -Message $_.Exception.Message
        Write-LogMessage -API 'Standards' -Tenant $Tenant -Message "Could not get the branding for $Tenant. This tenant might not have premium licenses available: $ErrorMessage" -Sev Error
    }

    # Get layoutTemplateType value using null-coalescing operator
    $layoutTemplateType = $Settings.layoutTemplateType.value ?? $Settings.layoutTemplateType

    $StateIsCorrect = ($CurrentState.signInPageText -eq $Settings.signInPageText) -and
                        ($CurrentState.usernameHintText -eq $Settings.usernameHintText) -and
                        ($CurrentState.loginPageTextVisibilitySettings.hideAccountResetCredentials -eq $Settings.hideAccountResetCredentials) -and
                        ($CurrentState.loginPageLayoutConfiguration.layoutTemplateType -eq $layoutTemplateType) -and
                        ($CurrentState.loginPageLayoutConfiguration.isHeaderShown -eq $Settings.isHeaderShown) -and
                        ($CurrentState.loginPageLayoutConfiguration.isFooterShown -eq $Settings.isFooterShown)

    If ($Settings.remediate -eq $true) {
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
                    Body        = [pscustomobject]@{
                        signInPageText                  = $Settings.signInPageText
                        usernameHintText                = $Settings.usernameHintText
                        loginPageTextVisibilitySettings = [pscustomobject]@{
                            hideAccountResetCredentials = $Settings.hideAccountResetCredentials
                        }
                        loginPageLayoutConfiguration    = [pscustomobject]@{
                            layoutTemplateType = $layoutTemplateType
                            isHeaderShown      = $Settings.isHeaderShown
                            isFooterShown      = $Settings.isFooterShown
                        }
                    } | ConvertTo-Json -Compress
                }
                $null = New-GraphPostRequest @GraphRequest
                Write-LogMessage -API 'Standards' -Tenant $Tenant -Message 'Successfully updated branding.' -Sev Info
            } catch {
                $ErrorMessage = Get-CippException -Exception $_
                Write-LogMessage -API 'Standards' -Tenant $Tenant -Message "Failed to update branding. Error: $($ErrorMessage.NormalizedError)" -Sev Error -LogData $ErrorMessage
            }
        }

    }

    If ($Settings.alert -eq $true) {

        if ($StateIsCorrect -eq $true) {
            Write-LogMessage -API 'Standards' -Tenant $Tenant -Message 'Branding is correctly set.' -Sev Info
        } else {
            Write-StandardsAlert -message 'Branding is incorrectly set.' -object ($CurrentState | Select-Object -Property signInPageText, usernameHintText, loginPageTextVisibilitySettings, loginPageLayoutConfiguration) -tenant $Tenant -standardName 'Branding' -standardId $Settings.standardId
            Write-LogMessage -API 'Standards' -Tenant $Tenant -Message 'Branding is incorrectly set.' -Sev Info
        }
    }

    If ($Settings.report -eq $true) {
        $state = $StateIsCorrect -eq $true ? $true : ($CurrentState | Select-Object -Property signInPageText, usernameHintText, loginPageTextVisibilitySettings, loginPageLayoutConfiguration)
        Set-CIPPStandardsCompareField -FieldName 'standards.Branding' -FieldValue $state -TenantFilter $Tenant
        Add-CIPPBPAField -FieldName 'Branding' -FieldValue [bool]$StateIsCorrect -StoreAs bool -Tenant $Tenant
    }
}
