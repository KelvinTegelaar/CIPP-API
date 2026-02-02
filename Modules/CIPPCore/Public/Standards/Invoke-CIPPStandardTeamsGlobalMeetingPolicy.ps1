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
            "CIS M365 5.0 (8.5.1)"
            "CIS M365 5.0 (8.5.2)"
            "CIS M365 5.0 (8.5.3)"
            "CIS M365 5.0 (8.5.4)"
            "CIS M365 5.0 (8.5.5)"
            "CIS M365 5.0 (8.5.6)"
        EXECUTIVETEXT
            Establishes security-focused default settings for Teams meetings, controlling who can join meetings, present content, and participate in chats. These policies balance collaboration needs with security requirements, ensuring meetings remain productive while protecting against unauthorized access and disruption.
        ADDEDCOMPONENT
            {"type":"autoComplete","required":true,"multiple":false,"creatable":false,"name":"standards.TeamsGlobalMeetingPolicy.DesignatedPresenterRoleMode","label":"Default value of the `Who can present?`","options":[{"label":"Everyone","value":"EveryoneUserOverride"},{"label":"People in my organization","value":"EveryoneInCompanyUserOverride"},{"label":"People in my organization and trusted organizations","value":"EveryoneInSameAndFederatedCompanyUserOverride"},{"label":"Only organizer","value":"OrganizerOnlyUserOverride"}]}
            {"type":"switch","name":"standards.TeamsGlobalMeetingPolicy.AllowAnonymousUsersToJoinMeeting","label":"Allow anonymous users to join meeting"}
            {"type":"autoComplete","required":false,"multiple":false,"creatable":false,"name":"standards.TeamsGlobalMeetingPolicy.AutoAdmittedUsers","label":"Who can bypass the lobby?","helperText":"If left blank, the current value will not be changed.","options":[{"label":"Only organizers and co-organizers","value":"OrganizerOnly"},{"label":"People in organization excluding guests","value":"EveryoneInCompanyExcludingGuests"},{"label":"People who were invited","value":"InvitedUsers"}]}
            {"type":"autoComplete","required":true,"multiple":false,"creatable":false,"name":"standards.TeamsGlobalMeetingPolicy.MeetingChatEnabledType","label":"Meeting chat policy","options":[{"label":"On for everyone","value":"Enabled"},{"label":"On for everyone but anonymous users","value":"EnabledExceptAnonymous"},{"label":"Off for everyone","value":"Disabled"}]}
            {"type":"switch","name":"standards.TeamsGlobalMeetingPolicy.AllowExternalParticipantGiveRequestControl","label":"External participants can give or request control"}
        IMPACT
            Low Impact
        ADDEDDATE
            2024-11-12
        POWERSHELLEQUIVALENT
            Set-CsTeamsMeetingPolicy -AllowAnonymousUsersToJoinMeeting \$false -AllowAnonymousUsersToStartMeeting \$false -AutoAdmittedUsers \$AutoAdmittedUsers -AllowPSTNUsersToBypassLobby \$false -MeetingChatEnabledType EnabledExceptAnonymous -DesignatedPresenterRoleMode \$DesignatedPresenterRoleMode -AllowExternalParticipantGiveRequestControl \$false
        RECOMMENDEDBY
            "CIS"
        UPDATECOMMENTBLOCK
            Run the Tools\Update-StandardsComments.ps1 script to update this comment block
    .LINK
        https://docs.cipp.app/user-documentation/tenant/standards/list-standards
    #>
    param($Tenant, $Settings)
    $TestResult = Test-CIPPStandardLicense -StandardName 'TeamsGlobalMeetingPolicy' -TenantFilter $Tenant -RequiredCapabilities @('MCOSTANDARD', 'MCOEV', 'MCOIMP', 'TEAMS1', 'Teams_Room_Standard')

    if ($TestResult -eq $false) {
        return $true
    } #we're done.

    try {
        $CurrentState = New-TeamsRequest -TenantFilter $Tenant -Cmdlet 'Get-CsTeamsMeetingPolicy' -CmdParams @{Identity = 'Global' } |
            Select-Object AllowAnonymousUsersToJoinMeeting, AllowAnonymousUsersToStartMeeting, AutoAdmittedUsers, AllowPSTNUsersToBypassLobby, MeetingChatEnabledType, DesignatedPresenterRoleMode, AllowExternalParticipantGiveRequestControl
    } catch {
        $ErrorMessage = Get-NormalizedError -Message $_.Exception.Message
        Write-LogMessage -API 'Standards' -Tenant $Tenant -Message "Could not get the TeamsGlobalMeetingPolicy state for $Tenant. Error: $ErrorMessage" -Sev Error
        return
    }

    $MeetingChatEnabledType = $Settings.MeetingChatEnabledType.value ?? $Settings.MeetingChatEnabledType
    $DesignatedPresenterRoleMode = $Settings.DesignatedPresenterRoleMode.value ?? $Settings.DesignatedPresenterRoleMode
    $AutoAdmittedUsers = $Settings.AutoAdmittedUsers.value ?? $Settings.AutoAdmittedUsers ?? $CurrentState.AutoAdmittedUsers # Default to current state if not set, for backward compatibility pre v8.6.0

    $StateIsCorrect = ($CurrentState.AllowAnonymousUsersToJoinMeeting -eq $Settings.AllowAnonymousUsersToJoinMeeting) -and
    ($CurrentState.AllowAnonymousUsersToStartMeeting -eq $false) -and
    ($CurrentState.AutoAdmittedUsers -eq $AutoAdmittedUsers) -and
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
                AutoAdmittedUsers                          = $AutoAdmittedUsers
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

        $CurrentValue = @{
            AllowAnonymousUsersToJoinMeeting           = $CurrentState.AllowAnonymousUsersToJoinMeeting
            AllowAnonymousUsersToStartMeeting          = $CurrentState.AllowAnonymousUsersToStartMeeting
            AutoAdmittedUsers                          = $CurrentState.AutoAdmittedUsers
            AllowPSTNUsersToBypassLobby                = $CurrentState.AllowPSTNUsersToBypassLobby
            MeetingChatEnabledType                     = $CurrentState.MeetingChatEnabledType
            DesignatedPresenterRoleMode                = $CurrentState.DesignatedPresenterRoleMode
            AllowExternalParticipantGiveRequestControl = $CurrentState.AllowExternalParticipantGiveRequestControl
        }
        $ExpectedValue = @{
            AllowAnonymousUsersToJoinMeeting           = $Settings.AllowAnonymousUsersToJoinMeeting
            AllowAnonymousUsersToStartMeeting          = $false
            AutoAdmittedUsers                          = $AutoAdmittedUsers
            AllowPSTNUsersToBypassLobby                = $false
            MeetingChatEnabledType                     = $MeetingChatEnabledType
            DesignatedPresenterRoleMode                = $DesignatedPresenterRoleMode
            AllowExternalParticipantGiveRequestControl = $Settings.AllowExternalParticipantGiveRequestControl
        }
        Set-CIPPStandardsCompareField -FieldName 'standards.TeamsGlobalMeetingPolicy' -CurrentValue $CurrentValue -ExpectedValue $ExpectedValue -Tenant $Tenant
        Add-CIPPBPAField -FieldName 'TeamsGlobalMeetingPolicy' -FieldValue $StateIsCorrect -StoreAs bool -Tenant $Tenant

    }
}
