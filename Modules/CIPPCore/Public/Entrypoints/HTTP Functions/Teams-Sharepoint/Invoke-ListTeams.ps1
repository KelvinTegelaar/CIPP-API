using namespace System.Net

function Invoke-ListTeams {
    <#
    .SYNOPSIS
    List Microsoft Teams and their detailed information
    
    .DESCRIPTION
    Retrieves Microsoft Teams information including team details, channels, members, owners, and installed apps using Microsoft Graph API
    
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        Teams.Group.Read
        
    .NOTES
    Group: Teams & SharePoint
    Summary: List Teams
    Description: Retrieves Microsoft Teams information including team details, channels, members, owners, and installed apps using Microsoft Graph API with support for list view and detailed team view
    Tags: Teams,Channels,Members,Apps,Graph API
    Parameter: TenantFilter (string) [query] - Target tenant identifier
    Parameter: type (string) [query] - Query type: List (for team list) or Team (for detailed team info)
    Parameter: ID (string) [query] - Team ID for detailed team information (required when type=Team)
    Response: Returns different responses based on type parameter:
    Response: For type=List: Returns array of team objects with basic information
    Response: - id (string): Team unique identifier
    Response: - displayName (string): Team display name
    Response: - description (string): Team description
    Response: - visibility (string): Team visibility (Private, Public)
    Response: - mailNickname (string): Team mail nickname
    Response: For type=Team: Returns detailed team object with:
    Response: - Name (string): Team display name
    Response: - TeamInfo (array): Detailed team information
    Response: - ChannelInfo (array): Team channels
    Response: - Members (array): Team members (non-owners)
    Response: - Owners (array): Team owners
    Response: - InstalledApps (array): Installed team apps
    Example: [
      {
        "id": "12345678-1234-1234-1234-123456789012",
        "displayName": "Project Alpha",
        "description": "Team for Project Alpha development",
        "visibility": "Private",
        "mailNickname": "projectalpha"
      }
    ]
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $APIName = $Request.Params.CIPPEndpoint
    $Headers = $Request.Headers
    Write-LogMessage -headers $Headers -API $APIName -message 'Accessed this API' -Sev 'Debug'

    # Interact with query parameters or the body of the request.
    $TenantFilter = $Request.Query.TenantFilter
    if ($request.query.type -eq 'List') {
        $GraphRequest = New-GraphGetRequest -uri "https://graph.microsoft.com/beta/groups?`$filter=resourceProvisioningOptions/Any(x:x eq 'Team')&`$select=id,displayName,description,visibility,mailNickname" -tenantid $TenantFilter | Sort-Object -Property displayName
    }
    $TeamID = $request.query.ID
    Write-Host $TeamID
    if ($request.query.type -eq 'Team') {
        $Team = New-GraphGetRequest -uri "https://graph.microsoft.com/beta/teams/$($TeamID)" -tenantid $TenantFilter -asapp $true
        $Channels = New-GraphGetRequest -uri "https://graph.microsoft.com/beta/teams/$($TeamID)/Channels" -tenantid $TenantFilter -asapp $true
        $UserList = New-GraphGetRequest -uri "https://graph.microsoft.com/beta/teams/$($TeamID)/Members" -tenantid $TenantFilter -asapp $true
        $AppsList = New-GraphGetRequest -uri "https://graph.microsoft.com/beta/teams/$($TeamID)/installedApps?`$expand=teamsAppDefinition" -tenantid $TenantFilter -asapp $true

        $Owners = $UserList | Where-Object -Property Roles -EQ 'Owner'
        $Members = $UserList | Where-Object -Property email -NotIn $owners.email
        $GraphRequest = [PSCustomObject]@{
            Name          = $team.DisplayName
            TeamInfo      = @($team)
            ChannelInfo   = @($channels)
            Members       = @($Members)
            Owners        = @($owners)
            InstalledApps = @($AppsList)
        }
    }


    # Associate values to output bindings by calling 'Push-OutputBinding'.
    Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
            StatusCode = [HttpStatusCode]::OK
            Body       = @($GraphRequest)
        })

}
