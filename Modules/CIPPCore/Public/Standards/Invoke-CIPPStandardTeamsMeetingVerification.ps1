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

    param(
        $Tenant,
        $Settings
    )

    # License / capability check
    $TestResult = Test-CIPPStandardLicense -StandardName 'TeamsMeetingVerification' -TenantFilter $Tenant -RequiredCapabilities @('MCOSTANDARD', 'MCOEV', 'MCOIMP', 'TEAMS1', 'Teams_Room_Standard')

    if ($TestResult -eq $false) {
        return $true  # No license/capability, nothing to do
    }

    # Helper: get current state
    function Get-TeamsMeetingVerificationState {
        param(
            $TenantFilter
        )
        return New-TeamsRequest -TenantFilter $TenantFilter -Cmdlet 'Get-CsTeamsMeetingPolicy' -CmdParams @{ Identity = 'Global' } |
            Select-Object -Property CaptchaVerificationForMeetingJoin
    }

    # Get current policy
    try {
        $CurrentState = Get-TeamsMeetingVerificationState -TenantFilter $Tenant
    } catch {
        $ErrorMessage = Get-NormalizedError -Message $_.Exception.Message
        Write-LogMessage -API 'Standards' -Tenant $Tenant -Message "Could not get the TeamsMeetingVerification state for $Tenant. Error: $ErrorMessage" -Sev Error
        return
    }

    # Resolve expected setting from $Settings
    $rawSetting = $null

    if ($null -ne $Settings.CaptchaVerificationForMeetingJoin) {
        # Most common CIPP pattern: direct property
        $rawSetting = $Settings.CaptchaVerificationForMeetingJoin
    } elseif ($Settings.standards -and
              $Settings.standards.TeamsMeetingVerification -and
              $Settings.standards.TeamsMeetingVerification.CaptchaVerificationForMeetingJoin) {
        # Alternate nested pattern
        $rawSetting = $Settings.standards.TeamsMeetingVerification.CaptchaVerificationForMeetingJoin
    }

    if ($null -eq $rawSetting) {
        # FIX: use the live current state instead of assuming a default
        $CaptchaVerificationForMeetingJoin = $CurrentState.CaptchaVerificationForMeetingJoin
    } elseif ($rawSetting -is [hashtable] -or $rawSetting -is [pscustomobject]) {
        # Handle autocomplete object like @{ label = '...'; value = '...' }
        $CaptchaVerificationForMeetingJoin = $rawSetting.value
    } else {
        $CaptchaVerificationForMeetingJoin = $rawSetting
    }

    $StateIsCorrect = ($CurrentState.CaptchaVerificationForMeetingJoin -eq $CaptchaVerificationForMeetingJoin)

    # Remediation
    if ($Settings.remediate -eq $true) {
        if ($StateIsCorrect -eq $true) {
            Write-LogMessage -API 'Standards' -Tenant $Tenant -Message 'Teams Meeting Verification Policy already set.' -Sev Info
        } else {
            $cmdParams = @{
                Identity                          = 'Global'
                CaptchaVerificationForMeetingJoin = $CaptchaVerificationForMeetingJoin
            }

            try {
                New-TeamsRequest -TenantFilter $Tenant -Cmdlet 'Set-CsTeamsMeetingPolicy' -CmdParams $cmdParams
                Write-LogMessage -API 'Standards' -Tenant $Tenant -Message 'Updated Teams Meeting Verification Policy.' -Sev Info

                # Refresh from service to confirm drift is resolved
                try {
                    $CurrentState = Get-TeamsMeetingVerificationState -TenantFilter $Tenant
                    $StateIsCorrect = ($CurrentState.CaptchaVerificationForMeetingJoin -eq $CaptchaVerificationForMeetingJoin)
                } catch {
                    $ErrorMessage = Get-NormalizedError -Message $_.Exception.Message
                    Write-LogMessage -API 'Standards' -Tenant $Tenant -Message "Unable to refresh TeamsMeetingVerification state after remediation. Error: $ErrorMessage" -Sev Warning
                }

            } catch {
                $ErrorMessage = Get-CippException -Exception $_
                Write-LogMessage -API 'Standards' -Tenant $Tenant -Message "Failed to set Teams Meeting Verification Policy. Error: $($ErrorMessage.NormalizedError)" -Sev Error -LogData $ErrorMessage
            }
        }
    }

    # Alerting
    if ($Settings.alert -eq $true) {
        if ($StateIsCorrect -eq $true) {
            Write-LogMessage -API 'Standards' -Tenant $Tenant -Message 'Teams Meeting Verification Policy is set correctly.' -Sev Info
        } else {
            Write-StandardsAlert -Message 'Teams Meeting Verification Policy is not set correctly.' -Object $CurrentState -Tenant $Tenant -StandardName 'TeamsMeetingVerification' -StandardId $Settings.standardId
            Write-LogMessage -API 'Standards' -Tenant $Tenant -Message 'Teams Meeting Verification Policy is not set correctly.' -Sev Info
        }
    }

    # Reporting
    if ($Settings.report -eq $true) {
        $CurrentStateForReport = @{
            CaptchaVerificationForMeetingJoin = $CurrentState.CaptchaVerificationForMeetingJoin
        }
        $ExpectedState = @{
            CaptchaVerificationForMeetingJoin = $CaptchaVerificationForMeetingJoin
        }

        Set-CIPPStandardsCompareField -FieldName 'standards.TeamsMeetingVerification' -CurrentValue $CurrentStateForReport -ExpectedValue $ExpectedState -Tenant $Tenant
        Add-CIPPBPAField -FieldName 'TeamsMeetingVerification' -FieldValue $StateIsCorrect -StoreAs bool -Tenant $Tenant
    }
}
