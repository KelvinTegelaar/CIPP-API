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
            "mediumimpact"
        ADDEDCOMPONENT
            {"type":"Select","label":"Select value","name":"standards.UserSubmissions.state","values":[{"label":"Enabled","value":"enable"},{"label":"Disabled","value":"disable"}]}
        IMPACT
            Medium Impact
        POWERSHELLEQUIVALENT
            New-ReportSubmissionPolicy or Set-ReportSubmissionPolicy
        RECOMMENDEDBY
        UPDATECOMMENTBLOCK
            Run the Tools\Update-StandardsComments.ps1 script to update this comment block
    .LINK
        https://docs.cipp.app/user-documentation/tenant/standards/edit-standards
    #>

    param($Tenant, $Settings)

    # Input validation
    if ($Settings.remediate -eq $true -or $Settings.alert -eq $true) {
        if (!($Settings.state -eq 'enable' -or $Settings.state -eq 'disable')) {
            Write-LogMessage -API 'Standards' -tenant $tenant -message 'UserSubmissions: Invalid state parameter set' -sev Error
            Return
        } 
    
        if (!([string]::IsNullOrWhiteSpace($Settings.email))) {
            if ($Settings.email -notmatch '@') {
                Write-LogMessage -API 'Standards' -tenant $tenant -message 'UserSubmissions: Invalid Email parameter set' -sev Error
                Return
            }
        }
    }
    
    $PolicyState = New-ExoRequest -tenantid $Tenant -cmdlet 'Get-ReportSubmissionPolicy'
    $RuleState = New-ExoRequest -tenantid $Tenant -cmdlet 'Get-ReportSubmissionRule'

    if ($Settings.state -eq 'enable') {
        if (([string]::IsNullOrWhiteSpace($Settings.email))) {
            $PolicyIsCorrect = ($PolicyState.EnableReportToMicrosoft -eq $true) -and
                               ($PolicyState.ReportJunkToCustomizedAddress -eq $false) -and
                               ($PolicyState.ReportNotJunkToCustomizedAddress -eq $false) -and
                               ($PolicyState.ReportPhishToCustomizedAddress -eq $false)
            $RuleIsCorrect = $true
        } else {
            $PolicyIsCorrect = ($PolicyState.EnableReportToMicrosoft -eq $true) -and
                               ($PolicyState.ReportJunkToCustomizedAddress -eq $true) -and
                               ($PolicyState.ReportJunkAddresses -eq $Settings.email) -and
                               ($PolicyState.ReportNotJunkToCustomizedAddress -eq $true) -and
                               ($PolicyState.ReportNotJunkAddresses -eq $Settings.email) -and
                               ($PolicyState.ReportPhishToCustomizedAddress -eq $true) -and
                               ($PolicyState.ReportPhishAddresses -eq $Settings.email)
            $RuleIsCorrect = ($RuleState.State -eq "Enabled") -and
                             ($RuleSteate.SentTo -eq $Settings.email)
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
    

    if ($Settings.report -eq $true) {
        if ($PolicyState.length -eq 0) {
            Add-CIPPBPAField -FieldName 'UserSubmissionPolicy' -FieldValue $false -StoreAs bool -Tenant $tenant
        } else {
            Add-CIPPBPAField -FieldName 'UserSubmissionPolicy' -FieldValue $StateIsCorrect -StoreAs bool -Tenant $tenant
        }
    }

    If ($Settings.remediate -eq $true) {

        # If policy is set correctly, log and skip setting the policy
        if ($StateIsCorrect -eq $true) {
            Write-LogMessage -API 'Standards' -tenant $Tenant -message 'User Submission policy is already configured' -sev Info
        } else {
            if ($Settings.state -eq 'enable') {
                if (([string]::IsNullOrWhiteSpace($Settings.email))) {
                    $PolicyParams = @{
                        EnableReportToMicrosoft             = $true
                        ReportJunkToCustomizedAddress       = $false
                        ReportNotJunkToCustomizedAddress    = $false
                        ReportPhishToCustomizedAddress      = $false
                    }
                } else {
                    $PolicyParams = @{
                        EnableReportToMicrosoft             = $true
                        ReportJunkToCustomizedAddress       = $true
                        ReportJunkAddresses                 = $Settings.email
                        ReportNotJunkToCustomizedAddress    = $true
                        ReportNotJunkAddresses              = $Settings.email
                        ReportPhishToCustomizedAddress      = $true
                        ReportPhishAddresses                = $Settings.email
                    }
                    $RuleParams = @{
                        SentTo                 = $Settings.email
                    }
                }
            } else {
                $PolicyParams = @{
                    EnableReportToMicrosoft             = $false
                    ReportJunkToCustomizedAddress       = $false
                    ReportNotJunkToCustomizedAddress    = $false
                    ReportPhishToCustomizedAddress      = $false
                }
            } 

            if ($PolicyState.length -eq 0) {
                try {
                    New-ExoRequest -tenantid $Tenant -cmdlet 'New-ReportSubmissionPolicy' -cmdparams $PolicyParams -UseSystemMailbox $true
                    Write-LogMessage -API 'Standards' -tenant $tenant -message "User Submission policy created." -sev Info
                } catch {
                    $ErrorMessage = Get-NormalizedError -Message $_.Exception.Message
                    Write-LogMessage -API 'Standards' -tenant $Tenant -message "Failed to create User Submission policy. Error: $ErrorMessage" -sev Error
                }
            } else {
                try {
                    $PolicyParams.Add('Identity',"DefaultReportSubmissionPolicy")
                    New-ExoRequest -tenantid $Tenant -cmdlet 'Set-ReportSubmissionPolicy' -cmdParams $PolicyParams -UseSystemMailbox $true
                    Write-LogMessage -API 'Standards' -tenant $tenant -message "User Submission policy state set to $($Settings.state)." -sev Info
                } catch {
                    $ErrorMessage = Get-NormalizedError -Message $_.Exception.Message
                    Write-LogMessage -API 'Standards' -tenant $Tenant -message "Failed to set User Submission policy state to $($Settings.state). Error: $ErrorMessage" -sev Error
                }  
            }
            
            if ($RuleParams) {
                if ($RuleState.length -eq 0) {
                    try {
                        $RuleParams.Add('Name',"DefaultReportSubmissionRule")
                        $RuleParams.Add('ReportSubmissionPolicy','DefaultReportSubmissionPolicy')
                        New-ExoRequest -tenantid $Tenant -cmdlet 'New-ReportSubmissionRule' -cmdparams $RuleParams -UseSystemMailbox $true
                        Write-LogMessage -API 'Standards' -tenant $tenant -message "User Submission rule created." -sev Info
                    } catch {
                        $ErrorMessage = Get-NormalizedError -Message $_.Exception.Message
                        Write-LogMessage -API 'Standards' -tenant $Tenant -message "Failed to create User Submission rule. Error: $ErrorMessage" -sev Error
                    }
                } else {
                    try {
                        $RuleParams.Add('Identity',"DefaultReportSubmissionRule")
                        New-ExoRequest -tenantid $Tenant -cmdlet 'Set-ReportSubmissionRule' -cmdParams $RuleParams -UseSystemMailbox $true
                        Write-LogMessage -API 'Standards' -tenant $tenant -message "User Submission rule set to enabled." -sev Info
                    } catch {
                        $ErrorMessage = Get-NormalizedError -Message $_.Exception.Message
                        Write-LogMessage -API 'Standards' -tenant $Tenant -message "Failed to enable User Submission rule. Error: $ErrorMessage" -sev Error
                    }  
                }
            }
        }
    }

    if ($Settings.alert -eq $true) {

        if ($StateIsCorrect -eq $true) {
            Write-LogMessage -API 'Standards' -tenant $tenant -message 'User Submission policy is properly configured.' -sev Info
        } else {
            if ($Policy.EnableReportToMicrosoft -eq $true) {
                Write-LogMessage -API 'Standards' -tenant $tenant -message 'User Submission policy is enabled but incorrectly configured' -sev Alert
            } else {
                Write-LogMessage -API 'Standards' -tenant $tenant -message 'User Submission policy is disabled.' -sev Alert
            }
        }
    }
}
