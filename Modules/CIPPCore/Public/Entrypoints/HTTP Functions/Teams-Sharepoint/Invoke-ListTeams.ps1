Function Invoke-ListTeams {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        Teams.Group.Read
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)
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


    return ([HttpResponseContext]@{
            StatusCode = [HttpStatusCode]::OK
            Body       = @($GraphRequest)
        })

}
