function Invoke-ExecTeamAction {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        Teams.Group.ReadWrite
    .DESCRIPTION
        Archives or unarchives a team; creates, edits, archives or deletes a channel; sets a standard channel's moderation; manages the members of a private or shared channel and a channel's website tabs.
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $APIName = $Request.Params.CIPPEndpoint
    $Headers = $Request.Headers
    $TenantFilter = $Request.Body.tenantFilter
    # Archive, Unarchive, CreateChannel, EditChannel, ArchiveChannel, UnarchiveChannel, DeleteChannel, SetChannelModeration,
    # AddChannelMember, RemoveChannelMember, SetChannelMemberRole, AddChannelTab, EditChannelTab or RemoveChannelTab.
    $Action = $Request.Body.Action
    # Team (Microsoft 365 group) id.
    $TeamID = $Request.Body.TeamID
    # Channel id, for channel actions.
    $ChannelID = $Request.Body.ChannelID
    # Channel membership id, for removing a member or changing a role.
    $MembershipId = $Request.Body.MembershipId
    # User id, for adding a channel member.
    $UserId = $Request.Body.UserId.value ?? $Request.Body.UserId
    # Owner or Member.
    $Role = $Request.Body.Role.value ?? $Request.Body.Role
    # New channel name.
    $DisplayName = $Request.Body.DisplayName
    # New channel description.
    $Description = $Request.Body.Description
    # standard, private or shared.
    $MembershipType = $Request.Body.MembershipType.value ?? $Request.Body.MembershipType
    # First owner of a new private or shared channel.
    $OwnerId = $Request.Body.OwnerId.value ?? $Request.Body.OwnerId
    # Moderation: everyone or moderators.
    $NewMessages = $Request.Body.NewMessages.value ?? $Request.Body.NewMessages
    # Moderation: everyone or authorAndModerators.
    $Replies = $Request.Body.Replies.value ?? $Request.Body.Replies
    # Moderation: whether bots and connectors can post.
    $AllowBots = $Request.Body.AllowBots
    $AllowConnectors = $Request.Body.AllowConnectors
    # Channel tab id, for editing or removing a tab.
    $TabId = $Request.Body.TabId
    # Website tab address (https).
    $Url = $Request.Body.Url

    $Guid = '^[0-9a-fA-F]{8}-([0-9a-fA-F]{4}-){3}[0-9a-fA-F]{12}$'
    $Team = "https://graph.microsoft.com/beta/teams/$TeamID"
    $Channel = "$Team/channels/$ChannelID"
    $UserBind = 'https://graph.microsoft.com/v1.0/users(''{0}'')'

    try {
        if ("$TeamID" -notmatch $Guid) { throw [System.ArgumentException]::new('TeamID must be a team id') }
        if ($Action -notin @('Archive', 'Unarchive', 'CreateChannel') -and "$ChannelID" -notmatch '^19:[^/?#\s]+@thread\.[a-z0-9]+$') {
            throw [System.ArgumentException]::new('ChannelID must be a channel id')
        }
        if ($Action -in @('RemoveChannelMember', 'SetChannelMemberRole') -and "$MembershipId" -notmatch '^[A-Za-z0-9+/=_-]+$') {
            throw [System.ArgumentException]::new('MembershipId must be a channel membership id')
        }
        if ($Action -in @('AddChannelMember', 'SetChannelMemberRole') -and $Role -notin @('Owner', 'Member')) {
            throw [System.ArgumentException]::new('Role must be Owner or Member')
        }
        $Roles = @(if ($Role -eq 'Owner') { 'owner' })
        if ($Action -in @('EditChannelTab', 'RemoveChannelTab') -and "$TabId" -notmatch $Guid) { throw [System.ArgumentException]::new('TabId must be a tab id') }
        if ($Action -eq 'AddChannelTab' -or ($Action -eq 'EditChannelTab' -and $Url)) {
            if (-not ([uri]::TryCreate("$Url", 'Absolute', [ref]$null)) -or "$Url" -notmatch '^https://') { throw [System.ArgumentException]::new('Url must be an https address') }
        }
        if ($Action -in @('CreateChannel', 'AddChannelTab') -and [string]::IsNullOrWhiteSpace($DisplayName)) {
            throw [System.ArgumentException]::new('DisplayName is required')
        }

        $Call = switch ($Action) {
            'Archive' {
                @{ Method = 'POST'; Uri = "$Team/archive"; Body = @{}
                    Message = 'Archiving the team. This can take a few minutes to finish.' }
            }
            'Unarchive' {
                @{ Method = 'POST'; Uri = "$Team/unarchive"; Body = @{}
                    Message = 'Unarchiving the team. This can take a few minutes to finish.' }
            }
            'CreateChannel' {
                $Type = if ($MembershipType) { "$MembershipType".ToLowerInvariant() } else { 'standard' }
                if ($Type -notin @('standard', 'private', 'shared')) { throw [System.ArgumentException]::new('MembershipType must be standard, private or shared') }
                $Body = @{ displayName = "$DisplayName".Trim(); description = "$Description"; membershipType = $Type }
                if ($Type -ne 'standard') {
                    # Private and shared channels need an owner when created by an application.
                    if ("$OwnerId" -notmatch $Guid) { throw [System.ArgumentException]::new('OwnerId is required for a private or shared channel') }
                    $Body.members = @(@{ '@odata.type' = '#microsoft.graph.aadUserConversationMember'; roles = @('owner'); 'user@odata.bind' = $UserBind -f $OwnerId })
                }
                @{ Method = 'POST'; Uri = "$Team/channels"; Body = $Body; Message = "Created the $Type channel '$($Body.displayName)'" }
            }
            'EditChannel' {
                # Graph rejects a rename to the current name, so the name is only sent when it changes.
                $Body = @{}
                if (-not [string]::IsNullOrWhiteSpace($DisplayName)) { $Body.displayName = "$DisplayName".Trim() }
                if ($null -ne $Description) { $Body.description = "$Description" }
                if ($Body.Count -eq 0) { throw [System.ArgumentException]::new('Give a new name or description for the channel') }
                @{ Method = 'PATCH'; Uri = $Channel; Body = $Body; Message = 'Updated the channel' }
            }
            'ArchiveChannel' {
                @{ Method = 'POST'; Uri = "$Channel/archive"; Body = @{}; Message = 'Archived the channel' }
            }
            'UnarchiveChannel' {
                @{ Method = 'POST'; Uri = "$Channel/unarchive"; Body = @{}; Message = 'Unarchived the channel' }
            }
            'SetChannelModeration' {
                if ($NewMessages -notin @('everyone', 'moderators')) { throw [System.ArgumentException]::new('NewMessages must be everyone or moderators') }
                if ($Replies -notin @('everyone', 'authorAndModerators')) { throw [System.ArgumentException]::new('Replies must be everyone or authorAndModerators') }
                @{ Method = 'PATCH'; Uri = $Channel; Message = 'Updated the channel moderation'
                    Body = @{ moderationSettings = @{ userNewMessageRestriction = $NewMessages; replyRestriction = $Replies; allowNewMessageFromBots = $AllowBots -eq $true; allowNewMessageFromConnectors = $AllowConnectors -eq $true } } }
            }
            'AddChannelTab' {
                @{ Method = 'POST'; Uri = "$Channel/tabs"; Message = "Added the tab '$("$DisplayName".Trim())'"
                    Body = @{ displayName = "$DisplayName".Trim(); 'teamsApp@odata.bind' = 'https://graph.microsoft.com/v1.0/appCatalogs/teamsApps/com.microsoft.teamspace.tab.web'
                        configuration = @{ entityId = $null; contentUrl = "$Url"; websiteUrl = "$Url"; removeUrl = $null } } }
            }
            'EditChannelTab' {
                $Body = @{}
                if (-not [string]::IsNullOrWhiteSpace($DisplayName)) { $Body.displayName = "$DisplayName".Trim() }
                if ($Url) { $Body.configuration = @{ contentUrl = "$Url"; websiteUrl = "$Url" } }
                if ($Body.Count -eq 0) { throw [System.ArgumentException]::new('Give a new name or address for the tab') }
                @{ Method = 'PATCH'; Uri = "$Channel/tabs/$TabId"; Body = $Body; Message = 'Updated the tab' }
            }
            'RemoveChannelTab' {
                @{ Method = 'DELETE'; Uri = "$Channel/tabs/$TabId"; Message = 'Removed the tab' }
            }
            'DeleteChannel' {
                @{ Method = 'DELETE'; Uri = $Channel; Message = 'Deleted the channel' }
            }
            'AddChannelMember' {
                if ("$UserId" -notmatch $Guid) { throw [System.ArgumentException]::new('UserId must be a user id') }
                @{ Method = 'POST'; Uri = "$Channel/members"; Message = "Added the user to the channel as $($Role.ToLower())"
                    Body = @{ '@odata.type' = '#microsoft.graph.aadUserConversationMember'; roles = $Roles; 'user@odata.bind' = $UserBind -f $UserId } }
            }
            'RemoveChannelMember' {
                @{ Method = 'DELETE'; Uri = "$Channel/members/$([uri]::EscapeDataString($MembershipId))"; Message = 'Removed the member from the channel' }
            }
            'SetChannelMemberRole' {
                @{ Method = 'PATCH'; Uri = "$Channel/members/$([uri]::EscapeDataString($MembershipId))"; Message = "Made the member a channel $($Role.ToLower())"
                    Body = @{ '@odata.type' = '#microsoft.graph.aadUserConversationMember'; roles = $Roles } }
            }
            default { throw [System.ArgumentException]::new("Action '$Action' is not supported") }
        }

        $GraphParams = @{ uri = $Call.Uri; tenantid = $TenantFilter; type = $Call.Method; AsApp = $true }
        if ($Call.Body) { $GraphParams.body = ConvertTo-Json -InputObject $Call.Body -Compress -Depth 5 }
        # Teams rejects partner (delegated) access for these calls, so they run as the application.
        $null = New-GraphPOSTRequest @GraphParams
        $Result = $Call.Message
        Write-LogMessage -headers $Headers -API $APIName -tenant $TenantFilter -message "$Result. Team $TeamID" -Sev 'Info'
        $StatusCode = [HttpStatusCode]::OK
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        $Result = "Failed to $Action. Error: $($ErrorMessage.NormalizedError)"
        Write-LogMessage -headers $Headers -API $APIName -tenant $TenantFilter -message "$Result Team $TeamID" -Sev 'Error' -LogData $ErrorMessage
        $StatusCode = Get-CippErrorStatusCode -ErrorRecord $_
    }

    return ([HttpResponseContext]@{
            StatusCode = $StatusCode
            Body       = @{ Results = $Result }
        })
}
