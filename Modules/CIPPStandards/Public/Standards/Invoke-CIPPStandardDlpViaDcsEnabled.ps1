function Invoke-CIPPStandardDlpViaDcsEnabled {
    <#
    .FUNCTIONALITY
        Internal
    .COMPONENT
        (APIName) DlpViaDcsEnabled
    .SYNOPSIS
        (Label) Set OWA DLP evaluation via DCS
    .DESCRIPTION
        (Helptext) Sets whether Outlook on the web uses Data Classification Services for DLP evaluation. See [Microsoft's policy tip reference](https://learn.microsoft.com/en-us/purview/dlp-ol365-win32-policy-tips#sensitive-information-types-that-support-policy-tips-for-outlook-perpetual-users).
        (DocsDescription) Configures whether Outlook on the web uses Data Classification Services (DCS)-based Data Loss Prevention (DLP) policy evaluation instead of Exchange-based evaluation. Review DLP policies before enabling this setting, as some legacy Exchange-based predicates are not supported with DCS-based evaluation. See [Microsoft's policy tip reference](https://learn.microsoft.com/en-us/purview/dlp-ol365-win32-policy-tips#sensitive-information-types-that-support-policy-tips-for-outlook-perpetual-users).
    .NOTES
        CAT
            Exchange Standards
        TAG
        EXECUTIVETEXT
            Improves how Outlook on the web applies Data Loss Prevention policies, giving users clearer guidance when sensitive information may be shared and helping reduce accidental data exposure.
        ADDEDCOMPONENT
            {"type":"autoComplete","multiple":false,"creatable":false,"label":"Select value","name":"standards.DlpViaDcsEnabled.state","options":[{"label":"Enabled","value":"true"},{"label":"Disabled","value":"false"}]}
        IMPACT
            Medium Impact
        ADDEDDATE
            2026-05-20
        POWERSHELLEQUIVALENT
            Set-OrganizationConfig -DlpViaDcsEnabled
        RECOMMENDEDBY
        REQUIREDCAPABILITIES
            "EXCHANGE_S_STANDARD"
            "EXCHANGE_S_ENTERPRISE"
            "EXCHANGE_S_STANDARD_GOV"
            "EXCHANGE_S_ENTERPRISE_GOV"
            "EXCHANGE_LITE"
        UPDATECOMMENTBLOCK
            Run the Tools\Update-StandardsComments.ps1 script to update this comment block
    .LINK
        https://docs.cipp.app/user-documentation/tenant/standards/alignment/templates/available-standards
    #>

    param($Tenant, $Settings)
    $TestResult = Test-CIPPStandardLicense -StandardName 'DlpViaDcsEnabled' -TenantFilter $Tenant -Preset Exchange #No Foundation because that does not allow powershell access

    if ($TestResult -eq $false) {
        return $true
    } #we're done.

    $state = $Settings.state.value ?? $Settings.state
    if ([string]::IsNullOrWhiteSpace($state) -or $state -eq 'Select a value') {
        Write-LogMessage -API 'Standards' -tenant $Tenant -message 'DLP via Data Classification Service state not selected, skipping.' -sev Error
        return
    }
    $WantedState = [System.Convert]::ToBoolean($state)

    try {
        $CurrentInfo = (New-ExoRequest -tenantid $Tenant -cmdlet 'Get-OrganizationConfig').DlpViaDcsEnabled
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Write-LogMessage -API 'Standards' -Tenant $Tenant -Message "Could not get the DLP via Data Classification Service state for $Tenant. Error: $($ErrorMessage.NormalizedError)" -Sev Error -LogData $ErrorMessage
        return
    }

    if ($Settings.remediate -eq $true) {
        if ($CurrentInfo -ne $WantedState) {
            try {
                $null = New-ExoRequest -tenantid $Tenant -cmdlet 'Set-OrganizationConfig' -cmdParams @{ DlpViaDcsEnabled = $WantedState }
                Write-LogMessage -API 'Standards' -tenant $Tenant -message "Successfully set DLP via Data Classification Service to $state." -sev Info
                $CurrentInfo = $WantedState
            } catch {
                $ErrorMessage = Get-CippException -Exception $_
                Write-LogMessage -API 'Standards' -tenant $Tenant -message "Failed to set DLP via Data Classification Service to $state. Error: $($ErrorMessage.NormalizedError)" -sev Error -LogData $ErrorMessage
            }
        } else {
            Write-LogMessage -API 'Standards' -tenant $Tenant -message "DLP via Data Classification Service is already set to $state." -sev Info
        }
    }

    if ($Settings.alert -eq $true) {
        if ($CurrentInfo -eq $WantedState) {
            Write-LogMessage -API 'Standards' -tenant $Tenant -message "DLP via Data Classification Service is set to $state." -sev Info
        } else {
            Write-StandardsAlert -message "DLP via Data Classification Service is not set to $state" -object $CurrentInfo -tenant $Tenant -standardName 'DlpViaDcsEnabled' -standardId $Settings.standardId
            Write-LogMessage -API 'Standards' -tenant $Tenant -message "DLP via Data Classification Service is not set to $state." -sev Info
        }
    }

    if ($Settings.report -eq $true) {
        Add-CIPPBPAField -FieldName 'DlpViaDcsEnabled' -FieldValue $CurrentInfo -StoreAs bool -Tenant $Tenant
        $CurrentValue = @{ DlpViaDcsEnabled = $CurrentInfo }
        $ExpectedValue = @{ DlpViaDcsEnabled = $WantedState }
        Set-CIPPStandardsCompareField -FieldName 'standards.DlpViaDcsEnabled' -CurrentValue $CurrentValue -ExpectedValue $ExpectedValue -Tenant $Tenant
    }
}
