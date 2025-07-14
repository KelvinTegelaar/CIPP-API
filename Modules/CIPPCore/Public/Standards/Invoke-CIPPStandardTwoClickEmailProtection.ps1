function Invoke-CIPPStandardTwoClickEmailProtection {
    <#
    .FUNCTIONALITY
        Internal
    .COMPONENT
        (APIName) TwoClickEmailProtection
    .SYNOPSIS
        (Label) Set two-click confirmation for encrypted emails in New Outlook
    .DESCRIPTION
        (Helptext) Configures the two-click confirmation requirement for viewing encrypted/protected emails in OWA and new Outlook. When enabled, users must click "View message" before accessing protected content, providing an additional layer of privacy protection.
        (DocsDescription) Configures the TwoClickMailPreviewEnabled setting in Exchange Online organization configuration. This security feature requires users to click "View message" before accessing encrypted or protected emails in Outlook on the web (OWA) and new Outlook for Windows. This provides additional privacy protection by preventing protected content from automatically displaying, giving users time to ensure their screen is not visible to others before viewing sensitive content. The feature helps protect against shoulder surfing and accidental disclosure of confidential information.
    .NOTES
        CAT
            Exchange Standards
        TAG
        ADDEDCOMPONENT
            {"type":"autoComplete","multiple":false,"creatable":false,"label":"Select value","name":"standards.TwoClickEmailProtection.state","options":[{"label":"Enabled","value":"enabled"},{"label":"Disabled","value":"disabled"}]}
        IMPACT
            Low Impact
        ADDEDDATE
            2025-06-13
        POWERSHELLEQUIVALENT
            Set-OrganizationConfig -TwoClickMailPreviewEnabled \$true \| \$false
        RECOMMENDEDBY
        UPDATECOMMENTBLOCK
            Run the Tools\Update-StandardsComments.ps1 script to update this comment block
    .LINK
        https://docs.cipp.app/user-documentation/tenant/standards/list-standards
    #>

    param($Tenant, $Settings)
    Test-CIPPStandardLicense -StandardName 'TwoClickEmailProtection' -TenantFilter $Tenant -RequiredCapabilities @('EXCHANGE_S_STANDARD', 'EXCHANGE_S_ENTERPRISE', 'EXCHANGE_LITE') #No Foundation because that does not allow powershell access
    ##$Rerun -Type Standard -Tenant $Tenant -Settings $Settings 'TwoClickEmailProtection'

    # Get state value using null-coalescing operator
    $State = $Settings.state.value ?? $Settings.state

    # Input validation
    if ([string]::IsNullOrWhiteSpace($State)) {
        Write-LogMessage -API 'Standards' -tenant $Tenant -message 'TwoClickEmailProtection: Invalid state parameter set' -sev Error
        Return
    }

    try {
        $CurrentState = (New-ExoRequest -tenantid $Tenant -cmdlet 'Get-OrganizationConfig').TwoClickMailPreviewEnabled
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Write-LogMessage -API 'Standards' -tenant $Tenant -message "Could not get current two-click email protection state. Error: $($ErrorMessage.NormalizedError)" -sev Error -LogData $ErrorMessage
        Return
    }

    $WantedState = $State -eq 'enabled' ? $true : $false
    $StateIsCorrect = $CurrentState -eq $WantedState ? $true : $false

    if ($Settings.remediate -eq $true) {
        Write-Host 'Time to remediate two-click email protection'

        if ($StateIsCorrect -eq $true) {
            Write-LogMessage -API 'Standards' -tenant $Tenant -message "Two-click email protection is already set to $State." -sev Info
        } else {
            try {
                $null = New-ExoRequest -tenantid $Tenant -cmdlet 'Set-OrganizationConfig' -cmdParams @{ TwoClickMailPreviewEnabled = $WantedState } -useSystemMailbox $true
                $StateIsCorrect = -not $StateIsCorrect # Toggle the state to reflect the change
                Write-LogMessage -API 'Standards' -tenant $Tenant -message "Successfully set two-click email protection to $State." -sev Info
            } catch {
                $ErrorMessage = Get-CippException -Exception $_
                Write-LogMessage -API 'Standards' -tenant $Tenant -message "Failed to set two-click email protection to $State. Error: $($ErrorMessage.NormalizedError)" -sev Error -LogData $ErrorMessage
            }
        }
    }

    if ($Settings.alert -eq $true) {
        if ($StateIsCorrect -eq $true) {
            Write-LogMessage -API 'Standards' -tenant $Tenant -message "Two-click email protection is correctly set to $State." -sev Info
        } else {
            Write-StandardsAlert -message "Two-click email protection is not correctly set to $State, but instead $($CurrentState ? 'enabled' : 'disabled')" -object @{TwoClickMailPreviewEnabled = $CurrentState } -tenant $Tenant -standardName 'TwoClickEmailProtection' -standardId $Settings.standardId
            Write-LogMessage -API 'Standards' -tenant $Tenant -message "Two-click email protection is not correctly set to $State, but instead $($CurrentState ? 'enabled' : 'disabled')" -sev Info
        }
    }

    if ($Settings.report -eq $true) {
        Set-CIPPStandardsCompareField -FieldName 'standards.TwoClickEmailProtection' -FieldValue $StateIsCorrect -Tenant $Tenant
        Add-CIPPBPAField -FieldName 'TwoClickEmailProtection' -FieldValue $StateIsCorrect -StoreAs bool -Tenant $Tenant
    }
}
