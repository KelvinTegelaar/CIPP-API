function Invoke-CIPPStandardAuthMethodsSettings {
    <#
    .FUNCTIONALITY
        Internal
    .COMPONENT
        (APIName) AuthMethodsSettings
    .SYNOPSIS
        (Label) Configure Authentication Methods Policy Settings
    .DESCRIPTION
        (Helptext) Configures the report suspicious activity settings and system credential preferences in the authentication methods policy
        (DocsDescription) This standard allows you to configure the reportSuspiciousActivitySettings and systemCredentialPreferences properties within the authentication methods policy.
    .NOTES
        CAT
            Entra Standards
        TAG
            "lowimpact"
        ADDEDCOMPONENT
            {"type":"autoComplete","multiple":false,"name":"standards.AuthMethodsSettings.ReportSuspiciousActivity","label":"Report Suspicious Activity Settings","options":[{"label":"Default","value":"default"},{"label":"Enabled","value":"enabled"},{"label":"Disabled","value":"disabled"}]}
            {"type":"autoComplete","multiple":false,"name":"standards.AuthMethodsSettings.SystemCredential","label":"System Credential Preferences","options":[{"label":"Default","value":"default"},{"label":"Enabled","value":"enabled"},{"label":"Disabled","value":"disabled"}]}
        IMPACT
            Low Impact
        POWERSHELLEQUIVALENT
            Update-MgBetaPolicyAuthenticationMethodPolicy
    .LINK
        https://docs.cipp.app/user-documentation/tenant/standards/list-standards/global-standards#low-impact
    #>

    param($Tenant, $Settings)

    Write-Host 'Time to run'
    # Get current authentication methods policy
    try {
        $CurrentPolicy = New-GraphGetRequest -Uri 'https://graph.microsoft.com/beta/policies/authenticationMethodsPolicy' -tenantid $Tenant -AsApp $true
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Write-LogMessage -API 'Standards' -tenant $tenant -message 'Failed to get authentication methods policy' -sev Error -LogData $ErrorMessage
        return
    }

    if ($Settings.report -eq $true) {
        Add-CIPPBPAField -FieldName 'ReportSuspiciousActivity' -FieldValue $CurrentPolicy.reportSuspiciousActivitySettings.state -StoreAs string -Tenant $tenant
        Add-CIPPBPAField -FieldName 'SystemCredential' -FieldValue $CurrentPolicy.systemCredentialPreferences.state -StoreAs string -Tenant $tenant
    }
    # Set wanted states
    $ReportSuspiciousActivityState = $Settings.ReportSuspiciousActivity.value ?? $Settings.ReportSuspiciousActivity
    $SystemCredentialState = $Settings.SystemCredential.value ?? $Settings.SystemCredential

    # Input validation
    $ValidStates = @('default', 'enabled', 'disabled')
    if (($Settings.remediate -eq $true -or $Settings.alert -eq $true) -and
        ($ReportSuspiciousActivityState -notin $ValidStates -or $SystemCredentialState -notin $ValidStates)) {
        Write-Host "ReportSuspiciousActivity: $($ReportSuspiciousActivityState)"
        Write-Host "SystemCredential: $($SystemCredentialState)"
        Write-LogMessage -API 'Standards' -tenant $tenant -message 'AuthMethodsPolicy: Invalid state parameter set' -sev Error
        return
    }



    # Check if states are set correctly
    $ReportSuspiciousActivityCorrect = if ($CurrentPolicy.reportSuspiciousActivitySettings.state -eq $ReportSuspiciousActivityState) { $true } else { $false }
    $SystemCredentialCorrect = if ($CurrentPolicy.systemCredentialPreferences.state -eq $SystemCredentialState) { $true } else { $false }
    $StateSetCorrectly = $ReportSuspiciousActivityCorrect -and $SystemCredentialCorrect

    if ($Settings.remediate -eq $true) {
        Write-Host 'Time to remediate'
        if ($StateSetCorrectly -eq $false) {
            try {
                $body = [PSCustomObject]@{
                    reportSuspiciousActivitySettings = $CurrentPolicy.reportSuspiciousActivitySettings
                    systemCredentialPreferences      = $CurrentPolicy.systemCredentialPreferences
                }
                $body.reportSuspiciousActivitySettings.state = $ReportSuspiciousActivityState
                $body.systemCredentialPreferences.state = $SystemCredentialState

                Write-Host "Body: $($body | ConvertTo-Json -Depth 10 -Compress)"
                # Update settings
                $null = New-GraphPostRequest -tenantid $tenant -Uri 'https://graph.microsoft.com/beta/policies/authenticationMethodsPolicy' -AsApp $true -Type PATCH -Body ($body | ConvertTo-Json -Depth 10 -Compress) -ContentType 'application/json'
                Write-LogMessage -API 'Standards' -tenant $tenant -message "Successfully configured authentication methods policy settings: Report Suspicious Activity ($ReportSuspiciousActivityState), System Credential Preferences ($SystemCredentialState)" -sev Info
            } catch {
                $ErrorMessage = Get-CippException -Exception $_
                Write-LogMessage -API 'Standards' -tenant $tenant -message 'Failed to configure authentication methods policy settings' -sev Error -LogData $ErrorMessage
            }
        } else {
            Write-LogMessage -API 'Standards' -tenant $tenant -message 'Authentication methods policy settings are already configured correctly' -sev Info
        }
    }

    if ($Settings.alert -eq $true) {
        if ($StateSetCorrectly -eq $true) {
            Write-LogMessage -API 'Standards' -tenant $tenant -message "Authentication methods policy settings are correctly configured: Report Suspicious Activity ($ReportSuspiciousActivityState), System Credential Preferences ($SystemCredentialState)" -sev Info
        } else {
            $CurrentReportState = $CurrentPolicy.reportSuspiciousActivitySettings.state
            $CurrentSystemState = $CurrentPolicy.systemCredentialPreferences.state
            Write-LogMessage -API 'Standards' -tenant $tenant -message "Authentication methods policy settings are not configured correctly. Current values: Report Suspicious Activity ($CurrentReportState), System Credential Preferences ($CurrentSystemState)" -sev Alert
        }
    }
}
