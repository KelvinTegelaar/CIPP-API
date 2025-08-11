function Invoke-CIPPStandardTeamsGlobalMeetingPolicy {
    <#
    .FUNCTIONALITY
        Internal
    .COMPONENT
        (APIName) TeamsGlobalMeetingPolicy
    .SYNOPSIS
        (Label) Define Global Meeting Policy for Teams
    .DESCRIPTION
        (Helptext) Defines the CIS recommended global meeting policy for Teams. This includes AllowAnonymousUsersToJoinMeeting, AllowAnonymousUsersToStartMeeting, AutoAdmittedUsers, AllowPSTNUsersToBypassLobby, MeetingChatEnabledType, DesignatedPresenterRoleMode, AllowExternalParticipantGiveRequestControl
        (DocsDescription) Defines the CIS recommended global meeting policy for Teams. This includes AllowAnonymousUsersToJoinMeeting, AllowAnonymousUsersToStartMeeting, AutoAdmittedUsers, AllowPSTNUsersToBypassLobby, MeetingChatEnabledType, DesignatedPresenterRoleMode, AllowExternalParticipantGiveRequestControl
    .NOTES
        CAT
            Teams Standards
        TAG
        ADDEDCOMPONENT
            {"type":"autoComplete","required":true,"multiple":false,"creatable":false,"name":"standards.TeamsGlobalMeetingPolicy.DesignatedPresenterRoleMode","label":"Default value of the `Who can present?`","options":[{"label":"EveryoneUserOverride","value":"EveryoneUserOverride"},{"label":"EveryoneInCompanyUserOverride","value":"EveryoneInCompanyUserOverride"},{"label":"EveryoneInSameAndFederatedCompanyUserOverride","value":"EveryoneInSameAndFederatedCompanyUserOverride"},{"label":"OrganizerOnlyUserOverride","value":"OrganizerOnlyUserOverride"}]}
            {"type":"switch","name":"standards.TeamsGlobalMeetingPolicy.AllowAnonymousUsersToJoinMeeting","label":"Allow anonymous users to join meeting"}
            {"type":"autoComplete","required":true,"multiple":false,"creatable":false,"name":"standards.TeamsGlobalMeetingPolicy.MeetingChatEnabledType","label":"Meeting chat policy","options":[{"label":"On for everyone","value":"Enabled"},{"label":"On for everyone but anonymous users","value":"EnabledExceptAnonymous"},{"label":"Off for everyone","value":"Disabled"}]}
            {"type":"switch","name":"standards.TeamsGlobalMeetingPolicy.AllowExternalParticipantGiveRequestControl","label":"External participants can give or request control"}
        IMPACT
            Low Impact
        ADDEDDATE
            2024-11-12
        POWERSHELLEQUIVALENT
            Set-CsTeamsMeetingPolicy -AllowAnonymousUsersToJoinMeeting \$false -AllowAnonymousUsersToStartMeeting \$false -AutoAdmittedUsers EveryoneInCompanyExcludingGuests -AllowPSTNUsersToBypassLobby \$false -MeetingChatEnabledType EnabledExceptAnonymous -DesignatedPresenterRoleMode \$DesignatedPresenterRoleMode -AllowExternalParticipantGiveRequestControl \$false
        RECOMMENDEDBY
            "CIS"
        UPDATECOMMENTBLOCK
            Run the Tools\Update-StandardsComments.ps1 script to update this comment block
    .LINK
        https://docs.cipp.app/user-documentation/tenant/standards/list-standards
    #>
    ##$Rerun -Type Standard -Tenant $Tenant -Settings $Settings 'TeamsGlobalMeetingPolicy'

    param($Tenant, $Settings)
    $TestResult = Test-CIPPStandardLicense -StandardName 'TeamsGlobalMeetingPolicy' -TenantFilter $Tenant -RequiredCapabilities @('MCOSTANDARD', 'MCOEV', 'MCOIMP', 'TEAMS1','Teams_Room_Standard')

    if ($TestResult -eq $false) {
        Write-Host "We're exiting as the correct license is not present for this standard."
        return $true
    } #we're done.

    try {
        $CurrentState = New-TeamsRequest -TenantFilter $Tenant -Cmdlet 'Get-CsTeamsMeetingPolicy' -CmdParams @{Identity = 'Global' } |
        Select-Object AllowAnonymousUsersToJoinMeeting, AllowAnonymousUsersToStartMeeting, AutoAdmittedUsers, AllowPSTNUsersToBypassLobby, MeetingChatEnabledType, DesignatedPresenterRoleMode, AllowExternalParticipantGiveRequestControl
    }
    catch {
        $ErrorMessage = Get-NormalizedError -Message $_.Exception.Message
        Write-LogMessage -API 'Standards' -Tenant $Tenant -Message "Could not get the TeamsGlobalMeetingPolicy state for $Tenant. Error: $ErrorMessage" -Sev Error
        return
    }

    $MeetingChatEnabledType = $Settings.MeetingChatEnabledType.value ?? $Settings.MeetingChatEnabledType
    $DesignatedPresenterRoleMode = $Settings.DesignatedPresenterRoleMode.value ?? $Settings.DesignatedPresenterRoleMode

    $StateIsCorrect = ($CurrentState.AllowAnonymousUsersToJoinMeeting -eq $Settings.AllowAnonymousUsersToJoinMeeting) -and
    ($CurrentState.AllowAnonymousUsersToStartMeeting -eq $false) -and
    ($CurrentState.AutoAdmittedUsers -eq 'EveryoneInCompanyExcludingGuests') -and
    ($CurrentState.AllowPSTNUsersToBypassLobby -eq $false) -and
    ($CurrentState.MeetingChatEnabledType -eq $MeetingChatEnabledType) -and
    ($CurrentState.DesignatedPresenterRoleMode -eq $DesignatedPresenterRoleMode) -and
    ($CurrentState.AllowExternalParticipantGiveRequestControl -eq $Settings.AllowExternalParticipantGiveRequestControl)


    if ($Settings.remediate -eq $true) {
        if ($StateIsCorrect -eq $true) {
            Write-LogMessage -API 'Standards' -tenant $Tenant -message 'Teams Global Policy already set.' -sev Info
        } else {
            $cmdParams = @{
                Identity                                   = 'Global'
                AllowAnonymousUsersToJoinMeeting           = $Settings.AllowAnonymousUsersToJoinMeeting
                AllowAnonymousUsersToStartMeeting          = $false
                AutoAdmittedUsers                          = 'EveryoneInCompanyExcludingGuests'
                AllowPSTNUsersToBypassLobby                = $false
                MeetingChatEnabledType                     = $MeetingChatEnabledType
                DesignatedPresenterRoleMode                = $DesignatedPresenterRoleMode
                AllowExternalParticipantGiveRequestControl = $Settings.AllowExternalParticipantGiveRequestControl
            }

            try {
                New-TeamsRequest -TenantFilter $Tenant -Cmdlet 'Set-CsTeamsMeetingPolicy' -CmdParams $cmdParams
                Write-LogMessage -API 'Standards' -tenant $Tenant -message 'Updated Teams Global Policy' -sev Info
            } catch {
                $ErrorMessage = Get-CippException -Exception $_
                Write-LogMessage -API 'Standards' -tenant $Tenant -message "Failed to set Teams Global Policy. Error: $($ErrorMessage.NormalizedError)" -sev Error -LogData $ErrorMessage
            }
        }
    }

    if ($Settings.alert -eq $true) {
        if ($StateIsCorrect -eq $true) {
            Write-LogMessage -API 'Standards' -tenant $Tenant -message 'Teams Global Policy is set correctly.' -sev Info
        } else {
            Write-StandardsAlert -message 'Teams Global Policy is not set correctly.' -object $CurrentState -tenant $Tenant -standardName 'TeamsGlobalMeetingPolicy' -standardId $Settings.standardId
            Write-LogMessage -API 'Standards' -tenant $Tenant -message 'Teams Global Policy is not set correctly.' -sev Info
        }
    }

    if ($Settings.report -eq $true) {

        if ($StateIsCorrect) {
            $FieldValue = $true
        } else {
            $FieldValue = $CurrentState
        }
        Set-CIPPStandardsCompareField -FieldName 'standards.TeamsGlobalMeetingPolicy' -FieldValue $FieldValue -Tenant $Tenant
        Add-CIPPBPAField -FieldName 'TeamsGlobalMeetingPolicy' -FieldValue $StateIsCorrect -StoreAs bool -Tenant $Tenant

    }
}
