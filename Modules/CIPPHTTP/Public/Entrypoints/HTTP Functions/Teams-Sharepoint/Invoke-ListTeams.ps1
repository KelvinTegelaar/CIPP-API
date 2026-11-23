Function Invoke-ListTeams {
    <#
    .FUNCTIONALITY
        Entrypoint,TenantGroup
    .ROLE
        Teams.Group.Read
    .DESCRIPTION
        Lists Microsoft Teams teams for a tenant. Supports UseReportDB=true query parameter to retrieve cached data from the reporting database for significantly better performance, especially when querying AllTenants.
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)
    # Interact with query parameters or the body of the request.
    $TenantFilter = $Request.Query.TenantFilter
    # Serve from the reporting database cache instead of live Graph. Much faster, especially for AllTenants.
    $UseReportDB = $Request.Query.UseReportDB -eq $true
    if ($request.query.type -eq 'List' -and ($TenantFilter -eq 'AllTenants' -or $UseReportDB)) {
        try {
            # Return one page per request as { Results, Metadata } with a continuation token in Metadata.nextLink.
            if ($Request.Query.manualPagination -eq $true) {
                # Cached rows per page, clamped between 250 and 10000. Defaults to 5000. Pages hold whole tenants.
                $PageSize = $Request.Query.PageSize -as [int]
                return ([HttpResponseContext]@{
                        StatusCode = [HttpStatusCode]::OK
                        # Continuation token from the previous page's Metadata.nextLink; opaque to callers.
                        Body       = Get-CIPPReportPage -TenantFilter $TenantFilter -Type 'Teams' -PageSize $PageSize -ContinuationToken $Request.Query.nextLink -Report { param($Tenant) Get-CIPPTeamsReport -TenantFilter $Tenant -ErrorAction Stop }
                    })
            }
            $GraphRequest = Get-CIPPTeamsReport -TenantFilter $TenantFilter -ErrorAction Stop
            $StatusCode = [HttpStatusCode]::OK
        } catch {
            $StatusCode = [HttpStatusCode]::InternalServerError
            $GraphRequest = $_.Exception.Message
        }
        return ([HttpResponseContext]@{
                StatusCode = $StatusCode
                Body       = @($GraphRequest)
            })
    }

    if ($request.query.type -eq 'List') {
        $GraphRequest = New-GraphGetRequest -uri "https://graph.microsoft.com/beta/groups?`$filter=resourceProvisioningOptions/Any(x:x eq 'Team')&`$select=id,displayName,description,visibility,mailNickname" -tenantid $TenantFilter | Sort-Object -Property displayName
    }
    $TeamID = $request.query.ID
    Write-Information $TeamID
    if ($request.query.type -eq 'Team') {
        $Team = New-GraphGetRequest -uri "https://graph.microsoft.com/beta/teams/$($TeamID)" -tenantid $TenantFilter -asapp $true
        $Channels = New-GraphGetRequest -uri "https://graph.microsoft.com/beta/teams/$($TeamID)/Channels" -tenantid $TenantFilter -asapp $true
        $UserList = New-GraphGetRequest -uri "https://graph.microsoft.com/beta/teams/$($TeamID)/Members" -tenantid $TenantFilter -asapp $true
        $AppsList = New-GraphGetRequest -uri "https://graph.microsoft.com/beta/teams/$($TeamID)/installedApps?`$expand=teamsAppDefinition" -tenantid $TenantFilter -asapp $true

        # Per-channel tab counts, and member counts and owners for private and shared channels, in one batch.
        $ChannelRequests = foreach ($Channel in @($Channels)) {
            @{ id = "tabs|$($Channel.id)"; method = 'GET'; url = "teams/$TeamID/channels/$($Channel.id)/tabs?`$select=id" }
            if ($Channel.membershipType -ne 'standard') {
                @{ id = "members|$($Channel.id)"; method = 'GET'; url = "teams/$TeamID/channels/$($Channel.id)/members?`$select=displayName,roles" }
            }
        }
        $ChannelDetails = @{}
        if ($ChannelRequests) {
            foreach ($Result in @(New-GraphBulkRequest -Requests @($ChannelRequests) -tenantid $TenantFilter -asapp $true)) {
                $ChannelDetails[$Result.id] = $Result.body.value
            }
        }
        foreach ($Channel in @($Channels)) {
            # A lookup that failed stays $null so the page shows nothing rather than a wrong count.
            $ChannelMembers = $ChannelDetails["members|$($Channel.id)"]
            $ChannelTabs = $ChannelDetails["tabs|$($Channel.id)"]
            $Channel | Add-Member -NotePropertyMembers @{
                tabCount    = if ($null -ne $ChannelTabs) { @($ChannelTabs).Count } else { $null }
                memberCount = if ($null -ne $ChannelMembers) { @($ChannelMembers).Count } else { $null }
                owners      = @(foreach ($Member in @($ChannelMembers)) { if ($Member.roles -contains 'owner') { $Member.displayName } }) -join ', '
            } -Force
        }

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
