function Invoke-CIPPStandardEXOOutboundSpamLimits {
    <#
    .FUNCTIONALITY
        Internal
    .COMPONENT
        (APIName) EXOOutboundSpamLimits
    .SYNOPSIS
        (Label) Set Exchange Outbound Spam Limits
    .DESCRIPTION
        (Helptext) Configures the outbound spam recipient limits (external per hour, internal per hour, per day) and the action to take when a limit is reached. The 'Set Outbound Spam Alert e-mail' standard is recommended to configure together with this one. 
        (DocsDescription) Configures the Exchange Online outbound spam recipient limits for external per hour, internal per hour, and per day, along with the action to take (e.g., BlockUser, Alert) when these limits are exceeded. This helps prevent abuse and manage email flow. Microsoft's recommendations can be found [here.](https://learn.microsoft.com/en-us/defender-office-365/recommended-settings-for-eop-and-office365#eop-outbound-spam-policy-settings) The 'Set Outbound Spam Alert e-mail' standard is recommended to configure together with this one.
    .NOTES
        CAT
            Exchange Standards
        TAG
            "CIS"
        ADDEDCOMPONENT
            {"type":"number","name":"standards.EXOOutboundSpamLimits.RecipientLimitExternalPerHour","label":"External Recipient Limit Per Hour","defaultValue":400}
            {"type":"number","name":"standards.EXOOutboundSpamLimits.RecipientLimitInternalPerHour","label":"Internal Recipient Limit Per Hour","defaultValue":800}
            {"type":"number","name":"standards.EXOOutboundSpamLimits.RecipientLimitPerDay","label":"Daily Recipient Limit","defaultValue":800}
            {"type":"autoComplete","multiple":false,"creatable":false,"name":"standards.EXOOutboundSpamLimits.ActionWhenThresholdReached","label":"Action When Threshold Reached","options":[{"label":"Alert","value":"Alert"},{"label":"Block User","value":"BlockUser"},{"label":"Block user from sending mail for the rest of the day","value":"BlockUserForToday"}]}
        IMPACT
            Low Impact
        ADDEDDATE
            2025-05-13
        POWERSHELLEQUIVALENT
            Set-HostedOutboundSpamFilterPolicy
        RECOMMENDEDBY
            "CIPP"
            "CIS"
        UPDATECOMMENTBLOCK
            Run the Tools\Update-StandardsComments.ps1 script to update this comment block
    .LINK
        https://docs.cipp.app/user-documentation/tenant/standards/list-standards
    #>

    param($Tenant, $Settings)
    $TestResult = Test-CIPPStandardLicense -StandardName 'EXOOutboundSpamLimits' -TenantFilter $Tenant -RequiredCapabilities @('EXCHANGE_S_STANDARD', 'EXCHANGE_S_ENTERPRISE', 'EXCHANGE_LITE') #No Foundation because that does not allow powershell access

    if ($TestResult -eq $false) {
        Write-Host "We're exiting as the correct license is not present for this standard."
        return $true
    } #we're done.

    # Make sure it handles the frontend being both autocomplete and a text field
    $ActionWhenThresholdReached = $Settings.ActionWhenThresholdReached.value ?? $Settings.ActionWhenThresholdReached

    # Input validation
    if ([Int32]$Settings.RecipientLimitExternalPerHour -lt 0 -or [Int32]$Settings.RecipientLimitExternalPerHour -gt 10000) {
        Write-LogMessage -API 'Standards' -tenant $Tenant -message 'EXOOutboundSpamLimits: Invalid RecipientLimitExternalPerHour parameter set. Must be between 0 and 10000.' -sev Error
        return
    }

    if ([Int32]$Settings.RecipientLimitInternalPerHour -lt 0 -or [Int32]$Settings.RecipientLimitInternalPerHour -gt 10000) {
        Write-LogMessage -API 'Standards' -tenant $Tenant -message 'EXOOutboundSpamLimits: Invalid RecipientLimitInternalPerHour parameter set. Must be between 0 and 10000.' -sev Error
        return
    }

    if ([Int32]$Settings.RecipientLimitPerDay -lt 0 -or [Int32]$Settings.RecipientLimitPerDay -gt 10000) {
        Write-LogMessage -API 'Standards' -tenant $Tenant -message 'EXOOutboundSpamLimits: Invalid RecipientLimitPerDay parameter set. Must be between 0 and 10000.' -sev Error
        return
    }

    $ValidActions = @('Alert', 'BlockUser', 'BlockUserForToday')
    if ($ActionWhenThresholdReached -notin $ValidActions) {
        Write-LogMessage -API 'Standards' -tenant $Tenant -message 'EXOOutboundSpamLimits: Invalid ActionWhenThresholdReached parameter set. Must be one of: Alert, BlockUser, BlockUserForToday.' -sev Error
        return
    }

    # Get current settings
    try {
        $CurrentInfo = New-ExoRequest -tenantid $Tenant -cmdlet 'Get-HostedOutboundSpamFilterPolicy' -cmdParams @{Identity = 'Default' } -Select 'RecipientLimitExternalPerHour, RecipientLimitInternalPerHour, RecipientLimitPerDay, ActionWhenThresholdReached' -useSystemMailbox $true |
        Select-Object -ExcludeProperty *data.type*
    }
    catch {
        $ErrorMessage = Get-NormalizedError -Message $_.Exception.Message
        Write-LogMessage -API 'Standards' -Tenant $Tenant -Message "Could not get the EXOOutboundSpamLimits state for $Tenant. Error: $ErrorMessage" -Sev Error
        return
    }

    # Check if settings are already correct
    $StateIsCorrect = ($CurrentInfo.RecipientLimitExternalPerHour -eq $Settings.RecipientLimitExternalPerHour) -and
                        ($CurrentInfo.RecipientLimitInternalPerHour -eq $Settings.RecipientLimitInternalPerHour) -and
                        ($CurrentInfo.RecipientLimitPerDay -eq $Settings.RecipientLimitPerDay) -and
                        ($CurrentInfo.ActionWhenThresholdReached -eq $ActionWhenThresholdReached)

    # Remediation
    If ($Settings.remediate -eq $true) {
        Write-Host 'Time to remediate'
        if ($StateIsCorrect -eq $false) {
            try {
                $null = New-ExoRequest -tenantid $Tenant -cmdlet 'Set-HostedOutboundSpamFilterPolicy' -cmdParams @{
                    Identity                      = 'Default'
                    RecipientLimitExternalPerHour = $Settings.RecipientLimitExternalPerHour
                    RecipientLimitInternalPerHour = $Settings.RecipientLimitInternalPerHour
                    RecipientLimitPerDay          = $Settings.RecipientLimitPerDay
                    ActionWhenThresholdReached    = $ActionWhenThresholdReached
                } -useSystemMailbox $true

                Write-LogMessage -API 'Standards' -tenant $Tenant -message "Set outbound spam limits: External=$($Settings.RecipientLimitExternalPerHour), Internal=$($Settings.RecipientLimitInternalPerHour), Daily=$($Settings.RecipientLimitPerDay), Action=$($ActionWhenThresholdReached)" -sev Info
            } catch {
                $ErrorMessage = Get-CippException -Exception $_
                Write-LogMessage -API 'Standards' -tenant $Tenant -message "Could not set outbound spam limits. $($ErrorMessage.NormalizedError)" -sev Error -LogData $ErrorMessage
            }
        } else {
            Write-LogMessage -API 'Standards' -tenant $Tenant -message 'Outbound spam limits are already set correctly' -sev Info
        }
    }

    # Alert
    if ($Settings.alert -eq $true) {
        if ($StateIsCorrect -eq $true) {
            Write-LogMessage -API 'Standards' -tenant $Tenant -message "Outbound spam limits are correctly configured: External=$($Settings.RecipientLimitExternalPerHour), Internal=$($Settings.RecipientLimitInternalPerHour), Daily=$($Settings.RecipientLimitPerDay), Action=$($ActionWhenThresholdReached)" -sev Info
        } else {
            Write-StandardsAlert -message 'Outbound spam limits are not configured correctly' -object $CurrentInfo -tenant $Tenant -standardName 'EXOOutboundSpamLimits' -standardId $Settings.standardId
            Write-LogMessage -API 'Standards' -tenant $Tenant -message 'Outbound spam limits are not configured correctly' -sev Info
        }
    }

    # Report
    if ($Settings.report -eq $true) {
        $State = $StateIsCorrect ? $true : $CurrentInfo
        Set-CIPPStandardsCompareField -FieldName 'standards.EXOOutboundSpamLimits' -FieldValue $State -TenantFilter $Tenant
        Add-CIPPBPAField -FieldName 'OutboundSpamLimitsConfigured' -FieldValue $StateIsCorrect -StoreAs bool -Tenant $Tenant
    }
}
