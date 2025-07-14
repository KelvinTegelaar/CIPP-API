function Invoke-CIPPStandardTeamsMeetingVerification {
    <#
    .FUNCTIONALITY
        Internal
    .COMPONENT
        (APIName) TeamsMeetingVerification
    .SYNOPSIS
        (Label) Meeting Verification (ReCaptcha) for Teams
    .DESCRIPTION
        (Helptext) Configures the CAPTCHA verification for external users joining Teams meetings. This helps prevent unauthorized AI notetakers and bots from joining meetings.
        (DocsDescription) Configures the CAPTCHA verification for external users joining Teams meetings. This helps prevent unauthorized AI notetakers and bots from joining meetings. When enabled, external users from untrusted organizations or anonymous users will need to complete a CAPTCHA verification before joining meetings.
    .NOTES
        CAT
            Teams Standards
        TAG
        ADDEDCOMPONENT
            {"type":"autoComplete","required":true,"multiple":false,"creatable":false,"name":"standards.TeamsMeetingVerification.CaptchaVerificationForMeetingJoin","label":"CAPTCHA verification for meeting join","options":[{"label":"Not Required","value":"NotRequired"},{"label":"Anonymous Users and Untrusted Organizations","value":"AnonymousUsersAndUntrustedOrganizations"}]}
        IMPACT
            Low Impact
        ADDEDDATE
            2025-06-14
        POWERSHELLEQUIVALENT
            Set-CsTeamsMeetingPolicy -Identity Global -CaptchaVerificationForMeetingJoin AnonymousUsersAndUntrustedOrganizations
        RECOMMENDEDBY
            "Microsoft"
        UPDATECOMMENTBLOCK
            Run the Tools\Update-StandardsComments.ps1 script to update this comment block
    .LINK
        https://docs.cipp.app/user-documentation/tenant/standards/list-standards
    .LINK
        https://learn.microsoft.com/en-us/microsoftteams/join-verification-check
    #>
    ##$Rerun -Type Standard -Tenant $Tenant -Settings $Settings 'TeamsMeetingVerification'

    param($Tenant, $Settings)
    Test-CIPPStandardLicense -StandardName 'TeamsMeetingVerification' -TenantFilter $Tenant -RequiredCapabilities @('MCOSTANDARD', 'MCOEV', 'MCOIMP', 'TEAMS1','Teams_Room_Standard')
    $CurrentState = New-TeamsRequest -TenantFilter $Tenant -Cmdlet 'Get-CsTeamsMeetingPolicy' -CmdParams @{Identity = 'Global' } | Select-Object CaptchaVerificationForMeetingJoin
    $CaptchaVerificationForMeetingJoin = $Settings.CaptchaVerificationForMeetingJoin.value ?? $Settings.CaptchaVerificationForMeetingJoin
    $StateIsCorrect = ($CurrentState.CaptchaVerificationForMeetingJoin -eq $CaptchaVerificationForMeetingJoin)

    if ($Settings.remediate -eq $true) {
        if ($StateIsCorrect -eq $true) {
            Write-LogMessage -API 'Standards' -tenant $Tenant -message 'Teams Meeting Verification Policy already set.' -sev Info
        } else {
            $cmdParams = @{
                Identity                         = 'Global'
                CaptchaVerificationForMeetingJoin = $CaptchaVerificationForMeetingJoin
            }

            try {
                New-TeamsRequest -TenantFilter $Tenant -Cmdlet 'Set-CsTeamsMeetingPolicy' -CmdParams $cmdParams
                Write-LogMessage -API 'Standards' -tenant $Tenant -message 'Updated Teams Meeting Verification Policy' -sev Info
            } catch {
                $ErrorMessage = Get-CippException -Exception $_
                Write-LogMessage -API 'Standards' -tenant $Tenant -message "Failed to set Teams Meeting Verification Policy. Error: $($ErrorMessage.NormalizedError)" -sev Error -LogData $ErrorMessage
            }
        }
    }

    if ($Settings.alert -eq $true) {
        if ($StateIsCorrect -eq $true) {
            Write-LogMessage -API 'Standards' -tenant $Tenant -message 'Teams Meeting Verification Policy is set correctly.' -sev Info
        } else {
            Write-StandardsAlert -message 'Teams Meeting Verification Policy is not set correctly.' -object $CurrentState -tenant $Tenant -standardName 'TeamsMeetingVerification' -standardId $Settings.standardId
            Write-LogMessage -API 'Standards' -tenant $Tenant -message 'Teams Meeting Verification Policy is not set correctly.' -sev Info
        }
    }

    if ($Settings.report -eq $true) {
        if ($StateIsCorrect) {
            $FieldValue = $true
        } else {
            $FieldValue = $CurrentState
        }
        Set-CIPPStandardsCompareField -FieldName 'standards.TeamsMeetingVerification' -FieldValue $FieldValue -Tenant $Tenant
        Add-CIPPBPAField -FieldName 'TeamsMeetingVerification' -FieldValue $StateIsCorrect -StoreAs bool -Tenant $Tenant
    }
}
