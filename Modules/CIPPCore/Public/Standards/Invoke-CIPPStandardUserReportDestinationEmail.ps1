function Invoke-CIPPStandardUserReportDestinationEmail {
    <#
    .FUNCTIONALITY
        Internal
    .COMPONENT
        (APIName) UserReportDestinationEmail
    .SYNOPSIS
        (Label) Set the destination email for user reported emails
    .DESCRIPTION
        (Helptext) Sets the destination for email when users report them as spam or phishing. Works well together with the 'Set the state of the built-in Report button in Outlook standard'.
        (DocsDescription) Sets the destination for email when users report them as spam or phishing. Works well together with the 'Set the state of the built-in Report button in Outlook standard'.
    .NOTES
        CAT
            Exchange Standards
        TAG
            "mediumimpact"
        ADDEDCOMPONENT
            {"type":"input","name":"standards.UserReportDestinationEmail.Email","label":"Destination email address"}
        IMPACT
            Medium Impact
        POWERSHELLEQUIVALENT
            New-ReportSubmissionRule or Set-ReportSubmissionRule
        RECOMMENDEDBY
        UPDATECOMMENTBLOCK
            Run the Tools\Update-StandardsComments.ps1 script to update this comment block
    .LINK
        https://docs.cipp.app/user-documentation/tenant/standards/edit-standards
    #>

    param($Tenant, $Settings)

    # Input validation
    if (([string]::IsNullOrWhiteSpace($Settings.Email) -or $Settings.Email -eq 'Select a value' -or $Settings.Email -notmatch '@') -and
        ($Settings.remediate -eq $true -or $Settings.alert -eq $true)) {
        Write-LogMessage -API 'Standards' -tenant $tenant -message 'UserReportDestinationEmail: Invalid Email parameter set' -sev Error
        Return
    }

    $CurrentState = New-ExoRequest -tenantid $Tenant -cmdlet 'Get-ReportSubmissionRule'
    $StateIsCorrect = if ($CurrentState.SentTo -eq $Settings.Email) { $true } else { $false }

    # Write-Host 'Current State:'
    # Write-Host (ConvertTo-Json -InputObject $CurrentState -Depth 5)
    # Write-Host 'State is correct: ' $StateIsCorrect

    If ($Settings.remediate -eq $true) {
        Write-Host 'Time to remediate!'

        if ($StateIsCorrect -eq $false) {
            try {
                if ($null -eq $CurrentState) {
                    New-ExoRequest -tenantid $Tenant -cmdlet 'New-ReportSubmissionRule' -cmdParams @{ Name = 'DefaultReportSubmissionRule'; ReportSubmissionPolicy = 'DefaultReportSubmissionPolicy'; SentTo = ($Settings.Email.Trim()); } -UseSystemMailbox $true
                    Write-LogMessage -API 'Standards' -tenant $tenant -message "User Report Destination Email set to $($Settings.Email)." -sev Info
                } else {
                    New-ExoRequest -tenantid $Tenant -cmdlet 'Set-ReportSubmissionRule' -cmdParams @{ Identity = $CurrentState.Identity; SentTo = ($Settings.Email.Trim()) } -UseSystemMailbox $true
                    Write-LogMessage -API 'Standards' -tenant $tenant -message "User Report Destination Email set to $($Settings.Email)." -sev Info
                }
            } catch {
                $ErrorMessage = Get-NormalizedError -Message $_.Exception.Message
                Write-LogMessage -API 'Standards' -tenant $tenant -message "Could not set User Report Destination Email to $($Settings.Email). Error: $ErrorMessage" -sev Error
            }
        } else {
            Write-LogMessage -API 'Standards' -tenant $tenant -message "User Report Destination Email is already set to $($Settings.Email)." -sev Info
        }
    }

    if ($Settings.alert -eq $true) {
        if ($StateIsCorrect) {
            Write-LogMessage -API 'Standards' -tenant $tenant -message "User Report Destination Email is set to $($Settings.Email)." -sev Info
        } else {
            Write-LogMessage -API 'Standards' -tenant $tenant -message "User Report Destination Email is not set to $($Settings.Email)." -sev Alert
        }
    }

    if ($Settings.report -eq $true) {
        Add-CIPPBPAField -FieldName 'UserReportDestinationEmail' -FieldValue $StateIsCorrect -StoreAs bool -Tenant $tenant
    }
}
