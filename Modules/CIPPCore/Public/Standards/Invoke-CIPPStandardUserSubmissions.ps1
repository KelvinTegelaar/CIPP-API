function Invoke-CIPPStandardUserSubmissions {
    <#
    .FUNCTIONALITY
        Internal
    .COMPONENT
        (APIName) UserSubmissions
    .SYNOPSIS
        (Label) Set the state of the built-in Report button in Outlook
    .DESCRIPTION
        (Helptext) Set the state of the spam submission button in Outlook
        (DocsDescription) Set the state of the built-in Report button in Outlook. This gives the users the ability to report emails as spam or phish.
    .NOTES
        CAT
            Exchange Standards
        TAG
        EXECUTIVETEXT
            Enables employees to easily report suspicious emails directly from Outlook, helping improve the organization's spam and phishing detection systems. This crowdsourced approach to security allows users to contribute to threat detection while providing valuable feedback to enhance email security filters.
        ADDEDCOMPONENT
            {"type":"autoComplete","multiple":false,"label":"Select value","name":"standards.UserSubmissions.state","options":[{"label":"Enabled","value":"enable"},{"label":"Disabled","value":"disable"}]}
            {"type":"textField","name":"standards.UserSubmissions.email","required":false,"label":"Destination email address"}
        IMPACT
            Medium Impact
        ADDEDDATE
            2024-06-28
        POWERSHELLEQUIVALENT
            New-ReportSubmissionPolicy or Set-ReportSubmissionPolicy and New-ReportSubmissionRule or Set-ReportSubmissionRule
        RECOMMENDEDBY
        UPDATECOMMENTBLOCK
            Run the Tools\Update-StandardsComments.ps1 script to update this comment block
    .LINK
        https://docs.cipp.app/user-documentation/tenant/standards/list-standards
    #>

    param($Tenant, $Settings)
    $TestResult = Test-CIPPStandardLicense -StandardName 'UserSubmissions' -TenantFilter $Tenant -RequiredCapabilities @('EXCHANGE_S_STANDARD', 'EXCHANGE_S_ENTERPRISE', 'EXCHANGE_S_STANDARD_GOV', 'EXCHANGE_S_ENTERPRISE_GOV', 'EXCHANGE_LITE') #No Foundation because that does not allow powershell access

    if ($TestResult -eq $false) {
        return $true
    } #we're done.

    # Get state value using null-coalescing operator
    $state = $Settings.state.value ?? $Settings.state
    $Email = Get-CIPPTextReplacement -TenantFilter $Tenant -Text $Settings.email

    # Input validation
    if ($Settings.remediate -eq $true -or $Settings.alert -eq $true) {
        if (!($state -eq 'enable' -or $state -eq 'disable')) {
            Write-LogMessage -API 'Standards' -tenant $Tenant -message 'UserSubmissions: Invalid state parameter set' -sev Error
            return
        }

        if (!([string]::IsNullOrWhiteSpace($Email))) {
            if ($Email -notmatch '@') {
                Write-LogMessage -API 'Standards' -tenant $Tenant -message 'UserSubmissions: Invalid Email parameter set' -sev Error
                return
            }
        }
    }

    try {
        $PolicyState = New-ExoRequest -tenantid $Tenant -cmdlet 'Get-ReportSubmissionPolicy'
        $RuleState = New-ExoRequest -tenantid $Tenant -cmdlet 'Get-ReportSubmissionRule'
    } catch {
        $ErrorMessage = Get-NormalizedError -Message $_.Exception.Message
        Write-LogMessage -API 'Standards' -Tenant $Tenant -Message "Could not get the UserSubmissions state for $Tenant. Error: $ErrorMessage" -Sev Error
    }

    if ($state -eq 'enable') {
        if (([string]::IsNullOrWhiteSpace($Email))) {
            $PolicyIsCorrect = ($PolicyState.EnableReportToMicrosoft -eq $true) -and
            ($PolicyState.ReportJunkToCustomizedAddress -eq $false) -and
            ($PolicyState.ReportNotJunkToCustomizedAddress -eq $false) -and
            ($PolicyState.ReportPhishToCustomizedAddress -eq $false)
            $RuleIsCorrect = $true
        } else {
            $PolicyIsCorrect = ($PolicyState.EnableReportToMicrosoft -eq $true) -and
            ($PolicyState.ReportJunkToCustomizedAddress -eq $true) -and
            ($PolicyState.ReportJunkAddresses -eq $Email) -and
            ($PolicyState.ReportNotJunkToCustomizedAddress -eq $true) -and
            ($PolicyState.ReportNotJunkAddresses -eq $Email) -and
            ($PolicyState.ReportPhishToCustomizedAddress -eq $true) -and
            ($PolicyState.ReportPhishAddresses -eq $Email)
            $RuleIsCorrect = ($RuleState.State -eq 'Enabled') -and
            ($RuleState.SentTo -eq $Email)
        }
    } else {
        if ($PolicyState.length -eq 0) {
            $PolicyIsCorrect = $true
            $RuleIsCorrect = $true
        } else {
            $PolicyIsCorrect = ($PolicyState.EnableReportToMicrosoft -eq $false) -and
            ($PolicyState.ReportJunkToCustomizedAddress -eq $false) -and
            ($PolicyState.ReportNotJunkToCustomizedAddress -eq $false) -and
            ($PolicyState.ReportPhishToCustomizedAddress -eq $false)
            $RuleIsCorrect = $true
        }
    }

    $StateIsCorrect = $PolicyIsCorrect -and $RuleIsCorrect

    if ($Settings.remediate -eq $true) {
        # If policy is set correctly, log and skip setting the policy
        if ($StateIsCorrect -eq $true) {
            Write-LogMessage -API 'Standards' -tenant $Tenant -message 'User Submission policy is already configured' -sev Info
        } else {
            if ($state -eq 'enable') {
                if (([string]::IsNullOrWhiteSpace($Email))) {
                    $PolicyParams = @{
                        EnableReportToMicrosoft          = $true
                        ReportJunkToCustomizedAddress    = $false
                        ReportJunkAddresses              = $null
                        ReportNotJunkToCustomizedAddress = $false
                        ReportNotJunkAddresses           = $null
                        ReportPhishToCustomizedAddress   = $false
                        ReportPhishAddresses             = $null
                    }
                } else {
                    $PolicyParams = @{
                        EnableReportToMicrosoft          = $true
                        ReportJunkToCustomizedAddress    = $true
                        ReportJunkAddresses              = $Email
                        ReportNotJunkToCustomizedAddress = $true
                        ReportNotJunkAddresses           = $Email
                        ReportPhishToCustomizedAddress   = $true
                        ReportPhishAddresses             = $Email
                    }
                    $RuleParams = @{
                        SentTo = $Email
                    }
                }
            } else {
                $PolicyParams = @{
                    EnableReportToMicrosoft          = $false
                    ReportJunkToCustomizedAddress    = $false
                    ReportNotJunkToCustomizedAddress = $false
                    ReportPhishToCustomizedAddress   = $false
                }
            }

            if ($PolicyState.length -eq 0) {
                try {
                    $null = New-ExoRequest -tenantid $Tenant -cmdlet 'New-ReportSubmissionPolicy' -cmdParams $PolicyParams -UseSystemMailbox $true
                    Write-LogMessage -API 'Standards' -tenant $Tenant -message 'User Submission policy created.' -sev Info
                } catch {
                    $ErrorMessage = Get-CippException -Exception $_
                    Write-LogMessage -API 'Standards' -tenant $Tenant -message "Failed to create User Submission policy. Error: $($ErrorMessage.NormalizedError)" -sev Error
                }
            } else {
                try {
                    $PolicyParams.Add('Identity', 'DefaultReportSubmissionPolicy')
                    $null = New-ExoRequest -tenantid $Tenant -cmdlet 'Set-ReportSubmissionPolicy' -cmdParams $PolicyParams -UseSystemMailbox $true
                    Write-LogMessage -API 'Standards' -tenant $Tenant -message "User Submission policy state set to $state." -sev Info
                } catch {
                    $ErrorMessage = Get-CippException -Exception $_
                    Write-LogMessage -API 'Standards' -tenant $Tenant -message "Failed to set User Submission policy state to $state. Error: $($ErrorMessage.NormalizedError)" -sev Error
                }
            }

            if ($RuleParams) {
                if ($RuleState.length -eq 0) {
                    try {
                        $RuleParams.Add('Name', 'DefaultReportSubmissionRule')
                        $RuleParams.Add('ReportSubmissionPolicy', 'DefaultReportSubmissionPolicy')
                        $null = New-ExoRequest -tenantid $Tenant -cmdlet 'New-ReportSubmissionRule' -cmdParams $RuleParams -UseSystemMailbox $true
                        Write-LogMessage -API 'Standards' -tenant $Tenant -message 'User Submission rule created.' -sev Info
                    } catch {
                        $ErrorMessage = Get-CippException -Exception $_
                        Write-LogMessage -API 'Standards' -tenant $Tenant -message "Failed to create User Submission rule. Error: $($ErrorMessage.NormalizedError)" -sev Error
                    }
                } else {
                    try {
                        $RuleParams.Add('Identity', 'DefaultReportSubmissionRule')
                        $null = New-ExoRequest -tenantid $Tenant -cmdlet 'Set-ReportSubmissionRule' -cmdParams $RuleParams -UseSystemMailbox $true
                        Write-LogMessage -API 'Standards' -tenant $Tenant -message 'User Submission rule set to enabled.' -sev Info
                    } catch {
                        $ErrorMessage = Get-CippException -Exception $_
                        Write-LogMessage -API 'Standards' -tenant $Tenant -message "Failed to enable User Submission rule. Error: $($ErrorMessage.NormalizedError)" -sev Error
                    }
                }
            }
        }
    }

    if ($Settings.alert -eq $true) {

        if ($StateIsCorrect -eq $true) {
            Write-LogMessage -API 'Standards' -tenant $Tenant -message 'User Submission policy is properly configured.' -sev Info
        } else {
            if ($Policy.EnableReportToMicrosoft -eq $true) {
                Write-StandardsAlert -message 'User Submission policy is enabled but incorrectly configured' -object $PolicyState -tenant $Tenant -standardName 'UserSubmissions' -standardId $Settings.standardId
                Write-LogMessage -API 'Standards' -tenant $Tenant -message 'User Submission policy is enabled but incorrectly configured' -sev Info
            } else {
                Write-StandardsAlert -message 'User Submission policy is disabled.' -object $PolicyState -tenant $Tenant -standardName 'UserSubmissions' -standardId $Settings.standardId
                Write-LogMessage -API 'Standards' -tenant $Tenant -message 'User Submission policy is disabled.' -sev Info
            }
        }
    }

    if ($Settings.report -eq $true) {
        if ($PolicyState.length -eq 0) {
            Add-CIPPBPAField -FieldName 'UserSubmissionPolicy' -FieldValue $false -StoreAs bool -Tenant $Tenant
        } else {
            Add-CIPPBPAField -FieldName 'UserSubmissionPolicy' -FieldValue $StateIsCorrect -StoreAs bool -Tenant $Tenant
        }

        $PolicyState = $PolicyState | Select-Object EnableReportToMicrosoft, ReportJunkToCustomizedAddress, ReportNotJunkToCustomizedAddress, ReportPhishToCustomizedAddress, ReportJunkAddresses, ReportNotJunkAddresses, ReportPhishAddresses
        $RuleState = $RuleState | Select-Object State, SentTo

        $CurrentValue = @{
            EnableReportToMicrosoft          = $PolicyState.EnableReportToMicrosoft
            ReportJunkToCustomizedAddress    = $PolicyState.ReportJunkToCustomizedAddress
            ReportNotJunkToCustomizedAddress = $PolicyState.ReportNotJunkToCustomizedAddress
            ReportPhishToCustomizedAddress   = $PolicyState.ReportPhishToCustomizedAddress
            ReportJunkAddresses              = $PolicyState.ReportJunkAddresses
            ReportNotJunkAddresses           = $PolicyState.ReportNotJunkAddresses
            ReportPhishAddresses             = $PolicyState.ReportPhishAddresses
            RuleState                        = @{
                State  = $RuleState.State
                SentTo = $RuleState.SentTo
            }
        }
        $ExpectedValue = @{
            EnableReportToMicrosoft          = $state -eq 'enable'
            ReportJunkToCustomizedAddress    = if ([string]::IsNullOrWhiteSpace($Email)) { $false } else { $true }
            ReportNotJunkToCustomizedAddress = if ([string]::IsNullOrWhiteSpace($Email)) { $false } else { $true }
            ReportPhishToCustomizedAddress   = if ([string]::IsNullOrWhiteSpace($Email)) { $false } else { $true }
            ReportJunkAddresses              = if ([string]::IsNullOrWhiteSpace($Email)) { $null } else { @($Email) }
            ReportNotJunkAddresses           = if ([string]::IsNullOrWhiteSpace($Email)) { $null } else { @($Email) }
            ReportPhishAddresses             = if ([string]::IsNullOrWhiteSpace($Email)) { $null } else { @($Email) }
            RuleState                        = if ([string]::IsNullOrWhiteSpace($Email)) {
                @{
                    State  = 'Disabled'
                    SentTo = $null
                }
            } else {
                @{
                    State  = 'Enabled'
                    SentTo = @($Email)
                }
            }
        }
        Set-CIPPStandardsCompareField -FieldName 'standards.UserSubmissions' -CurrentValue $CurrentValue -ExpectedValue $ExpectedValue -TenantFilter $Tenant
    }
}
