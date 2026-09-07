function Invoke-CIPPStandardTeamsGlobalMeetingPolicy {
    <#
    .FUNCTIONALITY
        Internal
    .COMPONENT
        (APIName) TeamsGlobalMeetingPolicy
    .SYNOPSIS
        (Label) Define Global Meeting Policy for Teams
    .DESCRIPTION
        (Helptext) Defines the CIS recommended global meeting policy for Teams. This includes AllowAnonymousUsersToJoinMeeting, AllowAnonymousUsersToStartMeeting, AutoAdmittedUsers, AllowPSTNUsersToBypassLobby, MeetingChatEnabledType, DesignatedPresenterRoleMode, AllowExternalParticipantGiveRequestControl, AllowParticipantGiveRequestControl, AllowExternalNonTrustedMeetingChat, AllowCloudRecording
        (DocsDescription) Defines the CIS recommended global meeting policy for Teams. This includes AllowAnonymousUsersToJoinMeeting, AllowAnonymousUsersToStartMeeting, AutoAdmittedUsers, AllowPSTNUsersToBypassLobby, MeetingChatEnabledType, DesignatedPresenterRoleMode, AllowExternalParticipantGiveRequestControl, AllowParticipantGiveRequestControl, AllowExternalNonTrustedMeetingChat, AllowCloudRecording
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
            {"type":"autoComplete","required":true,"multiple":false,"creatable":false,"name":"standards.TeamsGlobalMeetingPolicy.DesignatedPresenterRoleMode","label":"Default value of the `Who can present?`","options":[{"label":"Everyone","value":"EveryoneUserOverride"},{"label":"People in my organization","value":"EveryoneInCompanyUserOverride"},{"label":"Only organizer","value":"OrganizerOnlyUserOverride"}]}
            {"type":"switch","name":"standards.TeamsGlobalMeetingPolicy.AllowAnonymousUsersToJoinMeeting","label":"Allow anonymous users to join meeting"}
            {"type":"switch","name":"standards.TeamsGlobalMeetingPolicy.AllowAnonymousUsersToStartMeeting","label":"Allow anonymous users to start meeting"}
            {"type":"autoComplete","required":false,"multiple":false,"creatable":false,"name":"standards.TeamsGlobalMeetingPolicy.AutoAdmittedUsers","label":"Who can bypass the lobby?","helperText":"If left blank, the current value will not be changed.","options":[{"label":"Only organizers and co-organizers","value":"OrganizerOnly"},{"label":"People in organization excluding guests","value":"EveryoneInCompanyExcludingGuests"},{"label":"People in same or federated organizations","value":"EveryoneInSameAndFederatedCompany"},{"label":"People who were invited","value":"InvitedUsers"},{"label":"Everyone","value":"Everyone"}]}
            {"type":"switch","name":"standards.TeamsGlobalMeetingPolicy.AllowPSTNUsersToBypassLobby","label":"Allow dial-in users to bypass lobby"}
            {"type":"autoComplete","required":true,"multiple":false,"creatable":false,"name":"standards.TeamsGlobalMeetingPolicy.MeetingChatEnabledType","label":"Meeting chat policy","options":[{"label":"On for everyone","value":"Enabled"},{"label":"On for everyone but anonymous users","value":"EnabledExceptAnonymous"},{"label":"Off for everyone","value":"Disabled"}]}
            {"type":"switch","name":"standards.TeamsGlobalMeetingPolicy.AllowParticipantGiveRequestControl","label":"Participants can give or request control"}
            {"type":"switch","name":"standards.TeamsGlobalMeetingPolicy.AllowExternalParticipantGiveRequestControl","label":"External participants can give or request control"}
            {"type":"autoComplete","required":false,"multiple":false,"creatable":false,"name":"standards.TeamsGlobalMeetingPolicy.AllowExternalNonTrustedMeetingChat","label":"External meeting chat","helperText":"CIS 8.5.8 recommends Off. Leave blank to keep the tenant's current value.","options":[{"label":"Off (CIS recommended)","value":false},{"label":"On","value":true}]}
            {"type":"autoComplete","required":false,"multiple":false,"creatable":false,"name":"standards.TeamsGlobalMeetingPolicy.AllowCloudRecording","label":"Meeting cloud recording","helperText":"CIS 8.5.9 recommends Off. Leave blank to keep the tenant's current value.","options":[{"label":"Off (CIS recommended)","value":false},{"label":"On","value":true}]}
        IMPACT
            Low Impact
        ADDEDDATE
            2024-11-12
        POWERSHELLEQUIVALENT
            Set-CsTeamsMeetingPolicy -AllowAnonymousUsersToJoinMeeting \$false -AllowAnonymousUsersToStartMeeting \$false -AutoAdmittedUsers \$AutoAdmittedUsers -AllowPSTNUsersToBypassLobby \$false -MeetingChatEnabledType EnabledExceptAnonymous -DesignatedPresenterRoleMode \$DesignatedPresenterRoleMode -AllowExternalParticipantGiveRequestControl \$false -AllowParticipantGiveRequestControl \$false -AllowExternalNonTrustedMeetingChat \$false -AllowCloudRecording \$false
        RECOMMENDEDBY
            "CIS"
        REQUIREDCAPABILITIES
            "MCOSTANDARD"
            "MCOEV"
            "MCOIMP"
            "TEAMS1"
            "Teams_Room_Standard"
        UPDATECOMMENTBLOCK
            Run the Tools\Update-StandardsComments.ps1 script to update this comment block
    .LINK
        https://docs.cipp.app/user-documentation/tenant/standards/alignment/templates/available-standards
    #>
    param($Tenant, $Settings)
    $TestResult = Test-CIPPStandardLicense -StandardName 'TeamsGlobalMeetingPolicy' -TenantFilter $Tenant -Preset Teams

    if ($TestResult -eq $false) {
        return $true
    } #we're done.

    try {
        $CurrentState = New-TeamsRequestV2 -TenantFilter $Tenant -Type 'TeamsMeetingPolicy' -Action Get -Identity 'Global' |
            Select-Object AllowAnonymousUsersToJoinMeeting, AllowAnonymousUsersToStartMeeting, AutoAdmittedUsers, AllowPSTNUsersToBypassLobby, MeetingChatEnabledType, DesignatedPresenterRoleMode, AllowExternalParticipantGiveRequestControl, AllowParticipantGiveRequestControl, AllowExternalNonTrustedMeetingChat, AllowCloudRecording
    } catch {
        $ErrorMessage = Get-NormalizedError -Message $_.Exception.Message
        Write-LogMessage -API 'Standards' -Tenant $Tenant -Message "Could not get the TeamsGlobalMeetingPolicy state for $Tenant. Error: $ErrorMessage" -Sev Error
        return
    }

    $MeetingChatEnabledType = $Settings.MeetingChatEnabledType.value ?? $Settings.MeetingChatEnabledType
    $DesignatedPresenterRoleMode = $Settings.DesignatedPresenterRoleMode.value ?? $Settings.DesignatedPresenterRoleMode

    # Microsoft retired EveryoneInSameAndFederatedCompanyUserOverride; the ConfigApi now rejects it with a 400.
    # Templates saved before it was removed from the picker still carry the value, so fail with a clear reason.
    $ValidPresenterRoleModes = @('OrganizerOnlyUserOverride', 'EveryoneInCompanyUserOverride', 'EveryoneUserOverride')
    if ($DesignatedPresenterRoleMode -and $DesignatedPresenterRoleMode -notin $ValidPresenterRoleModes) {
        Write-LogMessage -API 'Standards' -tenant $Tenant -message "TeamsGlobalMeetingPolicy: '$DesignatedPresenterRoleMode' is no longer a valid value for 'Who can present?'. Microsoft retired this option; select one of $($ValidPresenterRoleModes -join ', ') in the standards template." -sev Error
        return
    }
    $AutoAdmittedUsers = $Settings.AutoAdmittedUsers.value ?? $Settings.AutoAdmittedUsers ?? $CurrentState.AutoAdmittedUsers # Default to current state if not set, for backward compatibility pre v8.6.0

    # Untoggled switches are absent from the settings; default them to $false (the CIS recommended value) so we never send null to the ConfigApi
    $AllowAnonymousUsersToJoinMeeting = $Settings.AllowAnonymousUsersToJoinMeeting ?? $false
    $AllowAnonymousUsersToStartMeeting = $Settings.AllowAnonymousUsersToStartMeeting ?? $false
    $AllowPSTNUsersToBypassLobby = $Settings.AllowPSTNUsersToBypassLobby ?? $false
    $AllowExternalParticipantGiveRequestControl = $Settings.AllowExternalParticipantGiveRequestControl ?? $false
    $AllowParticipantGiveRequestControl = $Settings.AllowParticipantGiveRequestControl ?? $false

    # Opt-in booleans (autoComplete Off/On, or blank to keep the tenant's current value). Unlike the
    # switches above, a blank here means "do not manage" so existing deployments are never surprised
    # into disabling external chat or cloud recording. The option value can arrive as a real bool or
    # as "true"/"false", so ToBoolean handles both; blank/absent falls back to the current state.
    $RawExternalChat = $Settings.AllowExternalNonTrustedMeetingChat.value ?? $Settings.AllowExternalNonTrustedMeetingChat
    $AllowExternalNonTrustedMeetingChat = if ($null -eq $RawExternalChat -or "$RawExternalChat" -eq '') { $CurrentState.AllowExternalNonTrustedMeetingChat } else { [System.Convert]::ToBoolean($RawExternalChat) }
    $RawCloudRecording = $Settings.AllowCloudRecording.value ?? $Settings.AllowCloudRecording
    $AllowCloudRecording = if ($null -eq $RawCloudRecording -or "$RawCloudRecording" -eq '') { $CurrentState.AllowCloudRecording } else { [System.Convert]::ToBoolean($RawCloudRecording) }

    $StateIsCorrect = ($CurrentState.AllowAnonymousUsersToJoinMeeting -eq $AllowAnonymousUsersToJoinMeeting) -and
    ($CurrentState.AllowAnonymousUsersToStartMeeting -eq $AllowAnonymousUsersToStartMeeting) -and
    ($CurrentState.AutoAdmittedUsers -eq $AutoAdmittedUsers) -and
    ($CurrentState.AllowPSTNUsersToBypassLobby -eq $AllowPSTNUsersToBypassLobby) -and
    ($CurrentState.MeetingChatEnabledType -eq $MeetingChatEnabledType) -and
    ($CurrentState.DesignatedPresenterRoleMode -eq $DesignatedPresenterRoleMode) -and
    ($CurrentState.AllowExternalParticipantGiveRequestControl -eq $AllowExternalParticipantGiveRequestControl) -and
    ($CurrentState.AllowParticipantGiveRequestControl -eq $AllowParticipantGiveRequestControl) -and
    ($CurrentState.AllowExternalNonTrustedMeetingChat -eq $AllowExternalNonTrustedMeetingChat) -and
    ($CurrentState.AllowCloudRecording -eq $AllowCloudRecording)


    if ($Settings.remediate -eq $true) {
        if ($StateIsCorrect -eq $true) {
            Write-LogMessage -API 'Standards' -tenant $Tenant -message 'Teams Global Policy already set.' -sev Info
        } else {
            $cmdParams = @{
                Identity                                   = 'Global'
                AllowAnonymousUsersToJoinMeeting           = $AllowAnonymousUsersToJoinMeeting
                AllowAnonymousUsersToStartMeeting          = $AllowAnonymousUsersToStartMeeting
                AutoAdmittedUsers                          = $AutoAdmittedUsers
                AllowPSTNUsersToBypassLobby                = $AllowPSTNUsersToBypassLobby
                MeetingChatEnabledType                     = $MeetingChatEnabledType
                DesignatedPresenterRoleMode                = $DesignatedPresenterRoleMode
                AllowExternalParticipantGiveRequestControl = $AllowExternalParticipantGiveRequestControl
                AllowParticipantGiveRequestControl         = $AllowParticipantGiveRequestControl
                AllowExternalNonTrustedMeetingChat         = $AllowExternalNonTrustedMeetingChat
                AllowCloudRecording                        = $AllowCloudRecording
            }

            try {
                $null = New-TeamsRequestV2 -TenantFilter $Tenant -Type 'TeamsMeetingPolicy' -Action Set -Parameters $cmdParams
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
            AllowParticipantGiveRequestControl         = $CurrentState.AllowParticipantGiveRequestControl
            AllowExternalNonTrustedMeetingChat         = $CurrentState.AllowExternalNonTrustedMeetingChat
            AllowCloudRecording                        = $CurrentState.AllowCloudRecording
        }
        $ExpectedValue = @{
            AllowAnonymousUsersToJoinMeeting           = $AllowAnonymousUsersToJoinMeeting
            AllowAnonymousUsersToStartMeeting          = $AllowAnonymousUsersToStartMeeting
            AutoAdmittedUsers                          = $AutoAdmittedUsers
            AllowPSTNUsersToBypassLobby                = $AllowPSTNUsersToBypassLobby
            MeetingChatEnabledType                     = $MeetingChatEnabledType
            DesignatedPresenterRoleMode                = $DesignatedPresenterRoleMode
            AllowExternalParticipantGiveRequestControl = $AllowExternalParticipantGiveRequestControl
            AllowParticipantGiveRequestControl         = $AllowParticipantGiveRequestControl
            AllowExternalNonTrustedMeetingChat         = $AllowExternalNonTrustedMeetingChat
            AllowCloudRecording                        = $AllowCloudRecording
        }
        Set-CIPPStandardsCompareField -FieldName 'standards.TeamsGlobalMeetingPolicy' -CurrentValue $CurrentValue -ExpectedValue $ExpectedValue -Tenant $Tenant
        Add-CIPPBPAField -FieldName 'TeamsGlobalMeetingPolicy' -FieldValue $StateIsCorrect -StoreAs bool -Tenant $Tenant

    }
}
