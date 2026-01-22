function Invoke-CIPPStandardTeamsMeetingVerification {
    <#
    .FUNCTIONALITY
        Internal
    .COMPONENT
        (APIName) TeamsMeetingVerification
    .SYNOPSIS
        (Label) Teams Meeting Verification (CAPTCHA)
    .DESCRIPTION
        (Helptext) Configures CAPTCHA verification for external users joining Teams meetings. This helps prevent unauthorized AI notetakers and bots from joining meetings.
        (DocsDescription) Configures CAPTCHA verification for external users joining Teams meetings. This security feature requires external participants to complete a CAPTCHA challenge before joining, which helps prevent unauthorized AI notetakers, bots, and other automated systems from accessing meetings.
    .NOTES
        CAT
            Teams Standards
        TAG
        EXECUTIVETEXT
            Requires external meeting participants to complete verification challenges before joining Teams meetings, preventing automated bots and unauthorized AI systems from accessing confidential discussions. This security measure protects against meeting infiltration while maintaining legitimate external collaboration.
        ADDEDCOMPONENT
            {"type":"autoComplete","multiple":false,"creatable":false,"label":"CAPTCHA Verification Setting","name":"standards.TeamsMeetingVerification.CaptchaVerificationForMeetingJoin","options":[{"label":"Not Required","value":"NotRequired"},{"label":"Anonymous Users and Untrusted Organizations","value":"AnonymousUsersAndUntrustedOrganizations"}]}
        IMPACT
            Low Impact
        ADDEDDATE
            2025-06-14
        POWERSHELLEQUIVALENT
            Set-CsTeamsMeetingPolicy -CaptchaVerificationForMeetingJoin
        RECOMMENDEDBY
            "CIPP"
        UPDATECOMMENTBLOCK
            Run the Tools\Update-StandardsComments.ps1 script to update this comment block
    .LINK
        https://docs.cipp.app/user-documentation/tenant/standards/list-standards
    #>

    param($Tenant, $Settings)
    $TestResult = Test-CIPPStandardLicense -StandardName 'TeamsMeetingVerification' -TenantFilter $Tenant -RequiredCapabilities @('MCOSTANDARD', 'MCOEV', 'MCOIMP', 'TEAMS1', 'Teams_Room_Standard')

    if ($TestResult -eq $false) {
        Write-Host "We're exiting as the correct license is not present for this standard."
        return $true
    } #we're done.

    try {
        $CurrentState = New-TeamsRequest -TenantFilter $Tenant -Cmdlet 'Get-CsTeamsMeetingPolicy' -CmdParams @{Identity = 'Global' } |
            Select-Object CaptchaVerificationForMeetingJoin
    } catch {
        $ErrorMessage = Get-NormalizedError -Message $_.Exception.Message
        Write-LogMessage -API 'Standards' -Tenant $Tenant -Message "Could not get the TeamsMeetingVerification state for $Tenant. Error: $ErrorMessage" -Sev Error
        return
    }

    $CaptchaVerificationForMeetingJoin = $Settings.CaptchaVerificationForMeetingJoin.value ?? $Settings.CaptchaVerificationForMeetingJoin
    $StateIsCorrect = ($CurrentState.CaptchaVerificationForMeetingJoin -eq $CaptchaVerificationForMeetingJoin)

    if ($Settings.remediate -eq $true) {
        if ($StateIsCorrect -eq $true) {
            Write-LogMessage -API 'Standards' -tenant $Tenant -message 'Teams Meeting Verification Policy already set.' -sev Info
        } else {
            $cmdParams = @{
                Identity                          = 'Global'
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
        $CurrentState = @{
            CaptchaVerificationForMeetingJoin = $CurrentState.CaptchaVerificationForMeetingJoin
        }
        $ExpectedState = @{
            CaptchaVerificationForMeetingJoin = $CaptchaVerificationForMeetingJoin
        }
        Set-CIPPStandardsCompareField -FieldName 'standards.TeamsMeetingVerification' -CurrentValue $CurrentState -ExpectedValue $ExpectedState -Tenant $Tenant
        Add-CIPPBPAField -FieldName 'TeamsMeetingVerification' -FieldValue $StateIsCorrect -StoreAs bool -Tenant $Tenant
    }
}
