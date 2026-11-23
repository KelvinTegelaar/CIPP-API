BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
    $Modules = Join-Path $RepoRoot 'Modules'
    $FunctionPath = Get-ChildItem -Path $Modules -Recurse -Filter 'Invoke-ExecTeamAction.ps1' -File | Select-Object -First 1 -ExpandProperty FullName

    class HttpResponseContext {
        [int]$StatusCode
        [object]$Body
    }
    $Accelerators = [PSObject].Assembly.GetType('System.Management.Automation.TypeAccelerators')
    if (-not ('HttpStatusCode' -as [type])) {
        $Accelerators::Add('HttpStatusCode', [System.Net.HttpStatusCode])
    }

    function New-GraphPOSTRequest { param($uri, $tenantid, $type, $body, $AsApp) }
    function Write-LogMessage { param($headers, $API, $tenant, $message, $Sev, $LogData) }
    function Get-CippException { param($Exception) @{ NormalizedError = $Exception.Exception.Message } }

    . (Join-Path $Modules 'CIPPCore/Public/Get-CippErrorStatusCode.ps1')
    . $FunctionPath

    $script:TeamId = '11111111-2222-3333-4444-555555555555'
    $script:UserId = '66666666-7777-8888-9999-000000000000'
    $script:ChannelId = '19:abc123@thread.tacv2'
    $script:Base = "https://graph.microsoft.com/beta/teams/$($script:TeamId)"

    function Invoke-Action {
        param([hashtable]$Body)
        $Full = @{ tenantFilter = 'contoso.com'; TeamID = $script:TeamId }
        foreach ($Key in $Body.Keys) { $Full[$Key] = $Body[$Key] }
        $Request = [pscustomobject]@{ Params = @{ CIPPEndpoint = 'ExecTeamAction' }; Headers = @{}; Body = [pscustomobject]$Full }
        Invoke-ExecTeamAction -Request $Request -TriggerMetadata $null
    }
}

Describe 'Invoke-ExecTeamAction' {
    BeforeEach {
        $script:Call = $null
        Mock New-GraphPOSTRequest { $script:Call = @{ Uri = $uri; Type = $type; Body = $(if ($body) { $body | ConvertFrom-Json }); AsApp = $AsApp; Tenant = $tenantid } }
    }

    It 'archives the team without the read-only option, which app-only calls reject' {
        $Response = Invoke-Action @{ Action = 'Archive'; SetSpoSiteReadOnlyForMembers = $true }

        $Response.StatusCode | Should -Be 200
        $script:Call.Uri | Should -Be "$($script:Base)/archive"
        $script:Call.Type | Should -Be 'POST'
        $script:Call.Body.PSObject.Properties.Name | Should -Not -Contain 'shouldSetSpoSiteReadOnlyForMembers'
        $script:Call.AsApp | Should -BeTrue
        $script:Call.Tenant | Should -Be 'contoso.com'
    }

    It 'unarchives the team' {
        $null = Invoke-Action @{ Action = 'Unarchive' }

        $script:Call.Uri | Should -Be "$($script:Base)/unarchive"
        $script:Call.Type | Should -Be 'POST'
    }

    It 'creates a standard channel without members' {
        $null = Invoke-Action @{ Action = 'CreateChannel'; DisplayName = ' Projects '; Description = 'Work' }

        $script:Call.Uri | Should -Be "$($script:Base)/channels"
        $script:Call.Body.displayName | Should -Be 'Projects'
        $script:Call.Body.membershipType | Should -Be 'standard'
        $script:Call.Body.PSObject.Properties.Name | Should -Not -Contain 'members'
    }

    It 'creates a <Type> channel with the chosen owner' -ForEach @(@{ Type = 'private' }, @{ Type = 'shared' }) {
        $Response = Invoke-Action @{ Action = 'CreateChannel'; DisplayName = 'Board'; MembershipType = @{ label = 'x'; value = $Type }; OwnerId = @{ label = 'Owner'; value = $script:UserId } }

        $Response.StatusCode | Should -Be 200
        $script:Call.Body.membershipType | Should -Be $Type
        $script:Call.Body.members[0].roles | Should -Be @('owner')
        $script:Call.Body.members[0].'user@odata.bind' | Should -Be "https://graph.microsoft.com/v1.0/users('$($script:UserId)')"
    }

    It 'refuses a private channel with no owner' {
        $Response = Invoke-Action @{ Action = 'CreateChannel'; DisplayName = 'Board'; MembershipType = 'private' }

        $Response.StatusCode | Should -Be 400
        Should -Invoke New-GraphPOSTRequest -Times 0
    }

    It 'deletes a channel' {
        $null = Invoke-Action @{ Action = 'DeleteChannel'; ChannelID = $script:ChannelId }

        $script:Call.Uri | Should -Be "$($script:Base)/channels/$($script:ChannelId)"
        $script:Call.Type | Should -Be 'DELETE'
    }

    It 'adds a channel member as <Role>' -ForEach @(@{ Role = 'Owner'; Roles = @('owner') }, @{ Role = 'Member'; Roles = @() }) {
        $null = Invoke-Action @{ Action = 'AddChannelMember'; ChannelID = $script:ChannelId; UserId = @{ value = $script:UserId }; Role = $Role }

        $script:Call.Uri | Should -Be "$($script:Base)/channels/$($script:ChannelId)/members"
        $script:Call.Type | Should -Be 'POST'
        @($script:Call.Body.roles) | Should -Be $Roles
        $script:Call.Body.'user@odata.bind' | Should -Be "https://graph.microsoft.com/v1.0/users('$($script:UserId)')"
    }

    It 'changes a channel member role' {
        $null = Invoke-Action @{ Action = 'SetChannelMemberRole'; ChannelID = $script:ChannelId; MembershipId = 'MCMjMiMjZDc3=='; Role = 'Owner' }

        $script:Call.Uri | Should -Be "$($script:Base)/channels/$($script:ChannelId)/members/MCMjMiMjZDc3%3D%3D"
        $script:Call.Type | Should -Be 'PATCH'
        @($script:Call.Body.roles) | Should -Be @('owner')
    }

    It 'encodes a membership id so a slash cannot add a path segment' {
        $null = Invoke-Action @{ Action = 'RemoveChannelMember'; ChannelID = $script:ChannelId; MembershipId = 'ab/cd+e==' }

        $script:Call.Uri | Should -Be "$($script:Base)/channels/$($script:ChannelId)/members/ab%2Fcd%2Be%3D%3D"
    }

    It 'removes a channel member' {
        $null = Invoke-Action @{ Action = 'RemoveChannelMember'; ChannelID = $script:ChannelId; MembershipId = 'MCMjMiMjZDc3==' }

        $script:Call.Uri | Should -Be "$($script:Base)/channels/$($script:ChannelId)/members/MCMjMiMjZDc3%3D%3D"
        $script:Call.Type | Should -Be 'DELETE'
    }

    It 'rejects <Case> without calling Graph' -ForEach @(
        @{ Case = 'an unknown action'; Body = @{ Action = 'Clone' } }
        @{ Case = 'a team id that is not a GUID'; Body = @{ Action = 'Archive'; TeamID = '../groups' } }
        @{ Case = 'a channel id with a path'; Body = @{ Action = 'DeleteChannel'; ChannelID = '19:a@thread.tacv2/members' } }
        @{ Case = 'a membership id with a space'; Body = @{ Action = 'RemoveChannelMember'; ChannelID = '19:a@thread.tacv2'; MembershipId = 'abc def' } }
        @{ Case = 'a missing role'; Body = @{ Action = 'SetChannelMemberRole'; ChannelID = '19:a@thread.tacv2'; MembershipId = 'abc' } }
        @{ Case = 'a user id that is not a GUID'; Body = @{ Action = 'AddChannelMember'; ChannelID = '19:a@thread.tacv2'; UserId = 'x'; Role = 'Member' } }
        @{ Case = 'a blank channel name'; Body = @{ Action = 'CreateChannel'; DisplayName = ' ' } }
        @{ Case = 'an unknown channel type'; Body = @{ Action = 'CreateChannel'; DisplayName = 'x'; MembershipType = 'public' } }
    ) {
        $Response = Invoke-Action $Body

        $Response.StatusCode | Should -Be 400
        Should -Invoke New-GraphPOSTRequest -Times 0
    }

    It 'renames a channel and sets its description' {
        $null = Invoke-Action @{ Action = 'EditChannel'; ChannelID = $script:ChannelId; DisplayName = ' Board '; Description = 'Directors' }

        $script:Call.Uri | Should -Be "$($script:Base)/channels/$($script:ChannelId)"
        $script:Call.Type | Should -Be 'PATCH'
        $script:Call.Body.displayName | Should -Be 'Board'
        $script:Call.Body.description | Should -Be 'Directors'
    }

    It 'changes only the description when no new name is given' {
        $null = Invoke-Action @{ Action = 'EditChannel'; ChannelID = $script:ChannelId; Description = '' }

        $script:Call.Body.PSObject.Properties.Name | Should -Not -Contain 'displayName'
        $script:Call.Body.description | Should -Be ''
    }

    It '<Action> posts to the channel <Path> action' -ForEach @(
        @{ Action = 'ArchiveChannel'; Path = 'archive' }
        @{ Action = 'UnarchiveChannel'; Path = 'unarchive' }
    ) {
        $null = Invoke-Action @{ Action = $Action; ChannelID = $script:ChannelId }

        $script:Call.Uri | Should -Be "$($script:Base)/channels/$($script:ChannelId)/$Path"
        $script:Call.Type | Should -Be 'POST'
        $script:Call.AsApp | Should -BeTrue
    }

    It 'sets moderation from picker values and switches' {
        $null = Invoke-Action @{ Action = 'SetChannelModeration'; ChannelID = $script:ChannelId; NewMessages = @{ value = 'moderators' }; Replies = 'authorAndModerators'; AllowBots = $true; AllowConnectors = 'false' }

        $script:Call.Type | Should -Be 'PATCH'
        $Settings = $script:Call.Body.moderationSettings
        $Settings.userNewMessageRestriction | Should -Be 'moderators'
        $Settings.replyRestriction | Should -Be 'authorAndModerators'
        $Settings.allowNewMessageFromBots | Should -BeOfType [bool]
        $Settings.allowNewMessageFromBots | Should -BeTrue
        $Settings.allowNewMessageFromConnectors | Should -BeFalse
        $Settings.allowNewMessageFromConnectors | Should -BeOfType [bool]
    }

    It 'adds a website tab' {
        $null = Invoke-Action @{ Action = 'AddChannelTab'; ChannelID = $script:ChannelId; DisplayName = 'Docs'; Url = 'https://contoso.sharepoint.com/sites/x/Shared%20Documents' }

        $script:Call.Uri | Should -Be "$($script:Base)/channels/$($script:ChannelId)/tabs"
        $script:Call.Type | Should -Be 'POST'
        $script:Call.Body.'teamsApp@odata.bind' | Should -Be 'https://graph.microsoft.com/v1.0/appCatalogs/teamsApps/com.microsoft.teamspace.tab.web'
        $script:Call.Body.configuration.contentUrl | Should -Be 'https://contoso.sharepoint.com/sites/x/Shared%20Documents'
        $script:Call.Body.configuration.websiteUrl | Should -Be 'https://contoso.sharepoint.com/sites/x/Shared%20Documents'
    }

    It 'edits only what was given on a tab' {
        $TabId = '99999999-8888-7777-6666-555555555555'
        $null = Invoke-Action @{ Action = 'EditChannelTab'; ChannelID = $script:ChannelId; TabId = $TabId; DisplayName = 'Renamed' }

        $script:Call.Uri | Should -Be "$($script:Base)/channels/$($script:ChannelId)/tabs/$TabId"
        $script:Call.Type | Should -Be 'PATCH'
        $script:Call.Body.displayName | Should -Be 'Renamed'
        $script:Call.Body.PSObject.Properties.Name | Should -Not -Contain 'configuration'
    }

    It 'removes a tab' {
        $TabId = '99999999-8888-7777-6666-555555555555'
        $null = Invoke-Action @{ Action = 'RemoveChannelTab'; ChannelID = $script:ChannelId; TabId = $TabId }

        $script:Call.Uri | Should -Be "$($script:Base)/channels/$($script:ChannelId)/tabs/$TabId"
        $script:Call.Type | Should -Be 'DELETE'
    }

    It 'rejects <Case> for the new channel actions' -ForEach @(
        @{ Case = 'an http tab address'; Body = @{ Action = 'AddChannelTab'; ChannelID = '19:a@thread.tacv2'; DisplayName = 'x'; Url = 'http://contoso.com' } }
        @{ Case = 'a script tab address'; Body = @{ Action = 'AddChannelTab'; ChannelID = '19:a@thread.tacv2'; DisplayName = 'x'; Url = 'javascript:alert(1)' } }
        @{ Case = 'a tab with no name'; Body = @{ Action = 'AddChannelTab'; ChannelID = '19:a@thread.tacv2'; Url = 'https://contoso.com' } }
        @{ Case = 'a tab id that is not a GUID'; Body = @{ Action = 'RemoveChannelTab'; ChannelID = '19:a@thread.tacv2'; TabId = '../x' } }
        @{ Case = 'a tab edit with nothing to change'; Body = @{ Action = 'EditChannelTab'; ChannelID = '19:a@thread.tacv2'; TabId = '99999999-8888-7777-6666-555555555555' } }
        @{ Case = 'a channel edit with nothing to change'; Body = @{ Action = 'EditChannel'; ChannelID = '19:a@thread.tacv2'; DisplayName = ' ' } }
        @{ Case = 'an unknown moderation value'; Body = @{ Action = 'SetChannelModeration'; ChannelID = '19:a@thread.tacv2'; NewMessages = 'owners'; Replies = 'everyone' } }
        @{ Case = 'archiving a channel without a channel id'; Body = @{ Action = 'ArchiveChannel' } }
    ) {
        $Response = Invoke-Action $Body

        $Response.StatusCode | Should -Be 400
        Should -Invoke New-GraphPOSTRequest -Times 0
    }

    It 'returns the Graph error with a failure status' {
        Mock New-GraphPOSTRequest { throw 'General channel cannot be deleted.' }

        $Response = Invoke-Action @{ Action = 'DeleteChannel'; ChannelID = $script:ChannelId }

        $Response.StatusCode | Should -Be 500
        $Response.Body.Results | Should -BeLike '*General channel cannot be deleted*'
    }
}
