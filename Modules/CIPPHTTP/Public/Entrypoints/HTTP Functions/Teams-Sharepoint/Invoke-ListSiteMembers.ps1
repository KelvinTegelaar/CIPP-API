Function Invoke-ListSiteMembers {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        Sharepoint.Site.Read
    .DESCRIPTION
        Lists the actual membership of a SharePoint site: the users in the site's associated
        Owners/Members/Visitors role groups via the SharePoint REST API with certificate
        authentication, plus site collection admins. On group-connected (Team) sites the role
        groups contain the backing M365 group as a claim; those are expanded through Graph so
        the real people are returned. Falls back to the site's hidden User Information List
        via Graph when the SharePoint REST API is unavailable (e.g. the tenant does not have
        the SharePoint application permission consented yet).
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $TenantFilter = $Request.Query.tenantFilter
    $SiteId = $Request.Query.SiteId
    $SiteUrl = $Request.Query.SiteUrl
    $Filter = $Request.Query.Filter

    # A SharePoint user entity is a guest/external identity when either guest flag is set or
    # the claims login carries the external-user or spo-guest marker.
    function Test-SPGuestUser($User) {
        [bool]$User.IsShareByEmailGuestUser -or [bool]$User.IsEmailAuthenticationGuestUser -or $User.LoginName -match '(?i)#ext#|urn%3aspo%3aguest'
    }

    try {
        if (-not $SiteUrl) {
            $SiteUrl = (New-GraphGetRequest -uri "https://graph.microsoft.com/v1.0/sites/$($SiteId)?`$select=webUrl" -tenantid $TenantFilter -AsApp $true).webUrl
        }

        $Members = [System.Collections.Generic.List[object]]::new()
        try {
            $SharePointInfo = Get-SharePointAdminLink -Public $false -tenantFilter $TenantFilter
            $Scope = "$($SharePointInfo.SharePointUrl)/.default"
            $JsonAccept = @{ Accept = 'application/json;odata=nometadata' }
            $BaseUri = "$($SiteUrl.TrimEnd('/'))/_api"

            $RoleGroups = [ordered]@{
                'Owners'   = 'associatedownergroup'
                'Members'  = 'associatedmembergroup'
                'Visitors' = 'associatedvisitorgroup'
            }
            foreach ($Role in $RoleGroups.Keys) {
                $Users = New-GraphGetRequest -uri "$BaseUri/web/$($RoleGroups[$Role])/users?`$select=Id,Title,Email,LoginName,PrincipalType,IsShareByEmailGuestUser,IsEmailAuthenticationGuestUser" -tenantid $TenantFilter -scope $Scope -extraHeaders $JsonAccept -UseCertificate -AsApp $true
                foreach ($User in $Users) {
                    if ($User.LoginName -match 'federateddirectoryclaimprovider\|([0-9a-fA-F-]{36})(_o)?$') {
                        # Group-connected site: the role group holds the backing M365 group as
                        # a claim ('_o' suffix = the group's owners). Expand it through Graph.
                        $GroupId = $Matches[1]
                        $GraphSegment = if ($Matches[2]) { 'owners' } else { 'members' }
                        try {
                            $GroupMembers = New-GraphGetRequest -uri "https://graph.microsoft.com/v1.0/groups/$GroupId/$($GraphSegment)?`$select=displayName,mail,userPrincipalName&`$top=999" -tenantid $TenantFilter -AsApp $true
                            foreach ($GroupMember in $GroupMembers) {
                                $Members.Add([PSCustomObject]@{
                                        Title             = $GroupMember.displayName
                                        Email             = $GroupMember.mail ?? $GroupMember.userPrincipalName
                                        LoginName         = $GroupMember.userPrincipalName
                                        UserPrincipalName = $GroupMember.userPrincipalName
                                        Group             = $Role
                                        Type              = 'User (via M365 Group)'
                                        IsGuest           = ($GroupMember.userPrincipalName -match '(?i)#ext#')
                                        IsSiteAdmin       = $false
                                    })
                            }
                        } catch {
                            # Could not expand the group; show the claim entity itself.
                            $Members.Add([PSCustomObject]@{
                                    Title             = $User.Title
                                    Email             = $User.Email
                                    LoginName         = $User.LoginName
                                    UserPrincipalName = $null
                                    Group             = $Role
                                    Type              = 'M365 Group'
                                    IsGuest           = $false
                                    IsSiteAdmin       = $false
                                })
                        }
                    } else {
                        $Type = switch ($User.PrincipalType) {
                            1 { 'User' }
                            4 { 'Security Group' }
                            8 { 'SharePoint Group' }
                            default { 'Other' }
                        }
                        $Members.Add([PSCustomObject]@{
                                Title             = $User.Title
                                Email             = $User.Email
                                LoginName         = $User.LoginName
                                UserPrincipalName = if ($User.PrincipalType -eq 1) { ($User.LoginName -split '\|')[-1] } else { $null }
                                Group             = $Role
                                Type              = $Type
                                IsGuest           = (Test-SPGuestUser $User)
                                IsSiteAdmin       = $false
                            })
                    }
                }
            }

            # Site collection admins: flag them on existing rows, add rows for admins that
            # are not in any role group.
            $Admins = New-GraphGetRequest -uri "$BaseUri/web/siteusers?`$filter=IsSiteAdmin eq true&`$select=Id,Title,Email,LoginName,PrincipalType,IsShareByEmailGuestUser,IsEmailAuthenticationGuestUser" -tenantid $TenantFilter -scope $Scope -extraHeaders $JsonAccept -UseCertificate -AsApp $true
            foreach ($Admin in $Admins) {
                $Existing = @($Members | Where-Object { $_.LoginName -eq $Admin.LoginName })
                if ($Existing.Count -gt 0) {
                    $Existing | ForEach-Object { $_.IsSiteAdmin = $true }
                } else {
                    $Members.Add([PSCustomObject]@{
                            Title             = $Admin.Title
                            Email             = $Admin.Email
                            LoginName         = $Admin.LoginName
                            UserPrincipalName = if ($Admin.PrincipalType -eq 1) { ($Admin.LoginName -split '\|')[-1] } else { $null }
                            Group             = 'Site Admins'
                            IsGuest           = (Test-SPGuestUser $Admin)
                            Type              = if ($Admin.PrincipalType -eq 1) { 'User' } elseif ($Admin.LoginName -match 'federateddirectoryclaimprovider') { 'M365 Group' } else { 'Other' }
                            IsSiteAdmin       = $true
                        })
                }
            }
        } catch {
            # SharePoint REST unavailable (e.g. no certificate/consent) - fall back to the
            # hidden User Information List via Graph. This lists everyone ever resolved on
            # the site rather than actual role group membership.
            Write-Information "ListSiteMembers falling back to User Information List: $($_.Exception.Message)"
            $Members.Clear()
            $Lists = New-GraphGetRequest -uri "https://graph.microsoft.com/beta/sites/$SiteId/lists?`$select=id,list,system" -tenantid $TenantFilter -AsApp $true
            $UIList = $Lists | Where-Object { $_.list.template -eq 'userInformation' } | Select-Object -First 1
            if ($UIList.id) {
                $Items = New-GraphGetRequest -uri "https://graph.microsoft.com/beta/sites/$SiteId/lists/$($UIList.id)/items?`$expand=fields" -tenantid $TenantFilter -AsApp $true
                foreach ($Item in $Items) {
                    $Members.Add([PSCustomObject]@{
                            Title             = $Item.fields.Title
                            Email             = $Item.fields.EMail
                            LoginName         = $Item.fields.UserName
                            UserPrincipalName = if ($Item.fields.UserName) { ($Item.fields.UserName -split '\|')[-1] } else { $null }
                            Group             = 'Site Users'
                            Type              = 'User'
                            IsGuest           = ($Item.fields.UserName -match '(?i)#ext#')
                            IsSiteAdmin       = [bool]$Item.fields.IsSiteAdmin
                        })
                }
            }
        }

        if ($Filter -eq 'External') {
            $Members = @($Members | Where-Object { $_.IsGuest })
        }

        $StatusCode = [HttpStatusCode]::OK
        $Body = @($Members)
    } catch {
        $StatusCode = [HttpStatusCode]::Forbidden
        $Body = Get-NormalizedError -Message $_.Exception.Message
    }

    return ([HttpResponseContext]@{
            StatusCode = $StatusCode
            Body       = @{ 'Results' = $Body }
        })
}
