Function Invoke-CIPPStandardTeamsGlobalMeetingPolicy {
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
            "lowimpact"
        ADDEDCOMPONENT
            {"type":"Select","name":"standards.TeamsGlobalMeetingPolicy.DesignatedPresenterRoleMode","label":"Default value of the `Who can present?`","values":[{"label":"EveryoneUserOverride","value":"EveryoneUserOverride"},{"label":"EveryoneInCompanyUserOverride","value":"EveryoneInCompanyUserOverride"},{"label":"EveryoneInSameAndFederatedCompanyUserOverride","value":"EveryoneInSameAndFederatedCompanyUserOverride"},{"label":"OrganizerOnlyUserOverride","value":"OrganizerOnlyUserOverride"}]}
        IMPACT
            Low Impact
        POWERSHELLEQUIVALENT
            Set-CsTeamsMeetingPolicy -AllowAnonymousUsersToJoinMeeting \$false -AllowAnonymousUsersToStartMeeting \$false -AutoAdmittedUsers EveryoneInCompanyExcludingGuests -AllowPSTNUsersToBypassLobby \$false -MeetingChatEnabledType EnabledExceptAnonymous -DesignatedPresenterRoleMode \$DesignatedPresenterRoleMode -AllowExternalParticipantGiveRequestControl \$false
        RECOMMENDEDBY
            "CIS 3.0"
        UPDATECOMMENTBLOCK
            Run the Tools\Update-StandardsComments.ps1 script to update this comment block
    .LINK
        https://docs.cipp.app/user-documentation/tenant/standards/edit-standards
    #>
    ##$Rerun -Type Standard -Tenant $Tenant -Settings $Settings 'TeamsGlobalMeetingPolicy'

    param($Tenant, $Settings)
    $CurrentState = New-TeamsRequest -TenantFilter $Tenant -Cmdlet 'Get-CsTeamsMeetingPolicy' -CmdParams @{Identity = 'Global' }
    | Select-Object AllowAnonymousUsersToJoinMeeting, AllowAnonymousUsersToStartMeeting, AutoAdmittedUsers, AllowPSTNUsersToBypassLobby, MeetingChatEnabledType, DesignatedPresenterRoleMode, AllowExternalParticipantGiveRequestControl

    if ($null -eq $Settings.DesignatedPresenterRoleMode) { $Settings.DesignatedPresenterRoleMode = $CurrentState.DesignatedPresenterRoleMode }
    if ($null -eq $Settings.AllowAnonymousUsersToJoinMeeting) { $Settings.AllowAnonymousUsersToJoinMeeting = $CurrentState.AllowAnonymousUsersToJoinMeeting }
    if ($null -eq $Settings.MeetingChatEnabledType) { $Settings.MeetingChatEnabledType = $CurrentState.MeetingChatEnabledType } # Enabled, EnabledExceptAnonymous, Disabled

    $StateIsCorrect = ($CurrentState.AllowAnonymousUsersToJoinMeeting -eq $Settings.AllowAnonymousUsersToJoinMeeting) -and
                        ($CurrentState.AllowAnonymousUsersToStartMeeting -eq $false) -and
                        ($CurrentState.AutoAdmittedUsers -eq 'EveryoneInCompanyExcludingGuests') -and
                        ($CurrentState.AllowPSTNUsersToBypassLobby -eq $false) -and
                        ($CurrentState.MeetingChatEnabledType -eq $Settings.MeetingChatEnabledType) -and
                        ($CurrentState.DesignatedPresenterRoleMode -eq $Settings.DesignatedPresenterRoleMode) -and
                        ($CurrentState.AllowExternalParticipantGiveRequestControl -eq $false)

    if ($Settings.remediate -eq $true) {
        if ($StateIsCorrect -eq $true) {
            Write-LogMessage -API 'Standards' -tenant $Tenant -message 'Teams Global Policy already set.' -sev Info
        } else {
            $cmdparams = @{
                Identity                                   = 'Global'
                AllowAnonymousUsersToJoinMeeting           = $Settings.AllowAnonymousUsersToJoinMeeting
                AllowAnonymousUsersToStartMeeting          = $false
                AutoAdmittedUsers                          = 'EveryoneInCompanyExcludingGuests'
                AllowPSTNUsersToBypassLobby                = $false
                MeetingChatEnabledType                     = $Settings.MeetingChatEnabledType
                DesignatedPresenterRoleMode                = $Settings.DesignatedPresenterRoleMode
                AllowExternalParticipantGiveRequestControl = $false
            }

            try {
                New-TeamsRequest -TenantFilter $Tenant -Cmdlet 'Set-CsTeamsMeetingPolicy' -CmdParams $cmdparams
                Write-LogMessage -API 'Standards' -tenant $Tenant -message 'Updated Teams Global Policy' -sev Info
            } catch {
                $ErrorMessage = Get-NormalizedError -Message $_.Exception.Message
                Write-LogMessage -API 'Standards' -tenant $Tenant -message "Failed to set Teams Global Policy. Error: $ErrorMessage" -sev Error
            }
        }
    }

    if ($Settings.alert -eq $true) {
        if ($StateIsCorrect -eq $true) {
            Write-LogMessage -API 'Standards' -tenant $Tenant -message 'Teams Global Policy is set correctly.' -sev Info
        } else {
            Write-LogMessage -API 'Standards' -tenant $Tenant -message 'Teams Global Policy is not set correctly.' -sev Alert
        }
    }

    if ($Setings.report -eq $true) {
        Add-CIPPBPAField -FieldName 'TeamsGlobalMeetingPolicy' -FieldValue $StateIsCorrect -StoreAs bool -Tenant $Tenant
    }
}
