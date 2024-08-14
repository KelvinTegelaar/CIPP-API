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
            "lowimpact"
        ADDEDCOMPONENT
            {"type":"input","name":"standards.Branding.signInPageText","label":"Sign-in page text"}
            {"type":"input","name":"standards.Branding.usernameHintText","label":"Username hint Text"}
            {"type":"boolean","name":"standards.Branding.hideAccountResetCredentials","label":"Hide self-service password reset"}
            {"type":"Select","label":"Visual Template","name":"standards.Branding.layoutTemplateType","values":[{"label":"Full-screen background","value":"default"},{"label":"Partial-screen background","value":"verticalSplit"}]}
            {"type":"boolean","name":"standards.Branding.isHeaderShown","label":"Show header"}
            {"type":"boolean","name":"standards.Branding.isFooterShown","label":"Show footer"}
        IMPACT
            Low Impact
        POWERSHELLEQUIVALENT
            Portal only
        RECOMMENDEDBY
        UPDATECOMMENTBLOCK
            Run the Tools\Update-StandardsComments.ps1 script to update this comment block
    .LINK
        https://docs.cipp.app/user-documentation/tenant/standards/edit-standards
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

    $StateIsCorrect = ($CurrentState.signInPageText -eq $Settings.signInPageText) -and
                        ($CurrentState.usernameHintText -eq $Settings.usernameHintText) -and
                        ($CurrentState.loginPageTextVisibilitySettings.hideAccountResetCredentials -eq $Settings.hideAccountResetCredentials) -and
                        ($CurrentState.loginPageLayoutConfiguration.layoutTemplateType -eq $Settings.layoutTemplateType) -and
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
                            layoutTemplateType = $Settings.layoutTemplateType
                            isHeaderShown      = $Settings.isHeaderShown
                            isFooterShown      = $Settings.isFooterShown
                        }
                    } | ConvertTo-Json -Compress
                }
                New-GraphPostRequest @GraphRequest
                Write-LogMessage -API 'Standards' -Tenant $Tenant -Message 'Successfully updated branding.' -Sev Info
            } catch {
                $ErrorMessage = Get-NormalizedError -Message $_.Exception.Message
                Write-LogMessage -API 'Standards' -Tenant $Tenant -Message "Failed to update branding. Error: $($ErrorMessage)" -Sev Error
            }
        }

    }

    If ($Settings.alert -eq $true) {

        if ($StateIsCorrect -eq $true) {
            Write-LogMessage -API 'Standards' -Tenant $Tenant -Message 'Branding is correctly set.' -Sev Info
        } else {
            Write-LogMessage -API 'Standards' -Tenant $Tenant -Message 'Branding is incorrectly set.' -Sev Alert
        }
    }

    If ($Settings.report -eq $true) {
        Add-CIPPBPAField -FieldName 'Branding' -FieldValue [bool]$StateIsCorrect -StoreAs bool -Tenant $Tenant
    }
}
