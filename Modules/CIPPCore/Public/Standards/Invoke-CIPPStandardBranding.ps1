function Invoke-CIPPStandardBranding {
    <#
    .FUNCTIONALITY
    Internal
    #>

    param($Tenant, $Settings)
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
