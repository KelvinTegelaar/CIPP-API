# Pester tests for Invoke-ListSiteUserAccess
# Covers the owners claim ('_o') of a group-connected site: it must resolve to the group's owners, not its members.

BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
    $FunctionPath = Join-Path $RepoRoot 'Modules/CIPPHTTP/Public/Entrypoints/HTTP Functions/Teams-Sharepoint/Invoke-ListSiteUserAccess.ps1'
    if (-not (Test-Path $FunctionPath)) { throw "Could not locate $FunctionPath" }

    class HttpResponseContext {
        [object]$StatusCode
        [object]$Body
    }
    $Accelerators = [PSObject].Assembly.GetType('System.Management.Automation.TypeAccelerators')
    if (-not ('HttpStatusCode' -as [type])) {
        $Accelerators::Add('HttpStatusCode', [System.Net.HttpStatusCode])
    }

    function Get-CIPPSharingLinks { param($TenantFilter) }
    function Get-CippException { param($Exception) [PSCustomObject]@{ NormalizedError = $Exception.Exception.Message } }
    function New-GraphGetRequest {
        param(
            $uri, $tenantid, $scope, $AsApp, $extraHeaders,
            [switch]$UseCertificate
        )
    }
    function Resolve-CIPPSharePointPermissionScope { param($SiteUrl, $ListId, $TenantFilter) }
    function Write-LogMessage { param($Headers, $API, $tenant, $message, $sev, $LogData) }

    . $FunctionPath

    # Object ids are neutral GUIDs. The group is a group-connected site's Microsoft 365 group.
    $script:UserId = '00000000-0000-0000-0000-0000000000a1'
    $script:OtherOwnerId = '00000000-0000-0000-0000-0000000000a2'
    $script:GroupId = '00000000-0000-0000-0000-0000000000c1'
    $script:OwnersClaim = "c:0o.c|federateddirectoryclaimprovider|$($script:GroupId)_o"
    $script:MembersClaim = "c:0o.c|federateddirectoryclaimprovider|$($script:GroupId)"

    function New-TestRequest {
        [pscustomobject]@{
            Params  = @{ CIPPEndpoint = 'ListSiteUserAccess' }
            Headers = @{}
            Query   = @{
                tenantFilter      = 'contoso.onmicrosoft.com'
                SiteUrl           = 'https://contoso.sharepoint.com/sites/team'
                UserPrincipalName = 'user@contoso.com'
            }
            Body    = @{}
        }
    }
}

Describe 'Invoke-ListSiteUserAccess owners claim on a group-connected site' {
    BeforeEach {
        # Fixture knobs a test can change before it calls the endpoint.
        $script:MemberOfGroupIds = @($script:GroupId)
        $script:GroupOwnerIds = @($script:OtherOwnerId)
        $script:OwnersReadFails = $false

        Mock -CommandName Get-CippException -MockWith { [PSCustomObject]@{ NormalizedError = $Exception.Exception.Message } }
        Mock -CommandName Write-LogMessage -MockWith { }
        Mock -CommandName Get-CIPPSharingLinks -MockWith { @() }
        Mock -CommandName Resolve-CIPPSharePointPermissionScope -MockWith {
            [PSCustomObject]@{
                BaseUri                  = 'https://contoso.sharepoint.com/sites/team/_api'
                Scope                    = 'https://contoso.sharepoint.com/.default'
                Headers                  = @{ Accept = 'application/json;odata=nometadata' }
                AssignmentUri            = 'https://contoso.sharepoint.com/sites/team/_api/web/roleassignments'
                IsLibrary                = $false
                TargetLabel              = 'site root'
                HasUniqueRoleAssignments = $true
            }
        }
        Mock -CommandName New-GraphGetRequest -MockWith {
            if ($uri -like '*/transitiveMemberOf*') {
                return @($script:MemberOfGroupIds | ForEach-Object { [PSCustomObject]@{ id = $_; displayName = 'Team' } })
            }
            if ($uri -like '*/groups/*/owners*') {
                if ($script:OwnersReadFails) { throw 'Request_ResourceNotFound' }
                return @($script:GroupOwnerIds | ForEach-Object { [PSCustomObject]@{ id = $_ } })
            }
            if ($uri -like '*/web/roleassignments*') {
                return @(
                    [PSCustomObject]@{
                        Member                 = [PSCustomObject]@{ Id = 3; Title = 'Team Owners'; LoginName = 'Team Owners'; PrincipalType = 8 }
                        RoleDefinitionBindings = @([PSCustomObject]@{ Name = 'Full Control'; RoleTypeKind = 5 })
                    }
                    [PSCustomObject]@{
                        Member                 = [PSCustomObject]@{ Id = 5; Title = 'Team Members'; LoginName = 'Team Members'; PrincipalType = 8 }
                        RoleDefinitionBindings = @([PSCustomObject]@{ Name = 'Edit'; RoleTypeKind = 6 })
                    }
                )
            }
            if ($uri -like '*/web/sitegroups(3)/users*') {
                return @([PSCustomObject]@{ Id = 20; Title = 'Team Owners'; LoginName = $script:OwnersClaim; PrincipalType = 4 })
            }
            if ($uri -like '*/web/sitegroups(5)/users*') {
                return @([PSCustomObject]@{ Id = 21; Title = 'Team'; LoginName = $script:MembersClaim; PrincipalType = 4 })
            }
            if ($uri -like '*/web/siteusers*') {
                return @([PSCustomObject]@{ Id = 20; Title = 'Team Owners'; LoginName = $script:OwnersClaim; PrincipalType = 4 })
            }
            if ($uri -like '*/v1.0/users/*') {
                return [PSCustomObject]@{ id = $script:UserId; displayName = 'Test User'; userPrincipalName = 'user@contoso.com'; mail = 'user@contoso.com'; userType = 'Member' }
            }
            throw "Unexpected Graph request: $uri"
        }
    }

    It 'does not report an ordinary group member as an owner or a site collection admin' {
        $Response = Invoke-ListSiteUserAccess -Request (New-TestRequest) -TriggerMetadata $null

        $Response.StatusCode | Should -Be ([System.Net.HttpStatusCode]::OK)
        $Paths = @($Response.Body.Results.Paths)
        @($Paths | Where-Object { $_.PermissionLevel -eq 'Full Control' }).Count | Should -Be 0
        @($Paths | Where-Object { $_.Route -eq 'Site collection admin' }).Count | Should -Be 0
        @($Paths | Where-Object { $_.Via -like '*(owners)*' }).Count | Should -Be 0
    }

    It 'still reports the member route that the members claim grants' {
        $Response = Invoke-ListSiteUserAccess -Request (New-TestRequest) -TriggerMetadata $null

        $Paths = @($Response.Body.Results.Paths)
        $Paths.Count | Should -Be 1
        $Paths[0].Route | Should -Be 'SharePoint group'
        $Paths[0].PermissionLevel | Should -Be 'Edit'
        $Response.Body.Results.HasAccess | Should -BeTrue
    }

    It 'reports a group owner as Full Control and as a site collection admin' {
        $script:GroupOwnerIds = @($script:OtherOwnerId, $script:UserId)

        $Response = Invoke-ListSiteUserAccess -Request (New-TestRequest) -TriggerMetadata $null

        $Paths = @($Response.Body.Results.Paths)
        $OwnerPath = @($Paths | Where-Object { $_.Route -eq 'SharePoint group' -and $_.PermissionLevel -eq 'Full Control' })
        $OwnerPath.Count | Should -Be 1
        $OwnerPath[0].Via | Should -BeLike 'Member of Team Owners (*(owners))'
        $AdminPath = @($Paths | Where-Object { $_.Route -eq 'Site collection admin' })
        $AdminPath.Count | Should -Be 1
        $AdminPath[0].PermissionLevel | Should -Be 'Full Control'
        $AdminPath[0].Via | Should -BeLike '*(owners)'
    }

    It 'reports an owner who is not a member of the group' {
        $script:MemberOfGroupIds = @()
        $script:GroupOwnerIds = @($script:UserId)

        $Response = Invoke-ListSiteUserAccess -Request (New-TestRequest) -TriggerMetadata $null

        $Paths = @($Response.Body.Results.Paths)
        @($Paths | Where-Object { $_.Route -eq 'SharePoint group' -and $_.PermissionLevel -eq 'Full Control' }).Count | Should -Be 1
        @($Paths | Where-Object { $_.Route -eq 'Site collection admin' }).Count | Should -Be 1
        @($Paths | Where-Object { $_.PermissionLevel -eq 'Edit' }).Count | Should -Be 0
    }

    It 'reads the group owners once per request' {
        $null = Invoke-ListSiteUserAccess -Request (New-TestRequest) -TriggerMetadata $null

        Should -Invoke New-GraphGetRequest -Times 1 -Exactly -ParameterFilter { $uri -like "*/groups/$($script:GroupId)/owners*" }
    }

    It 'keeps the other routes when the owners cannot be read' {
        $script:OwnersReadFails = $true

        $Response = Invoke-ListSiteUserAccess -Request (New-TestRequest) -TriggerMetadata $null

        $Response.StatusCode | Should -Be ([System.Net.HttpStatusCode]::OK)
        $Paths = @($Response.Body.Results.Paths)
        @($Paths | Where-Object { $_.PermissionLevel -eq 'Full Control' }).Count | Should -Be 0
        @($Paths | Where-Object { $_.PermissionLevel -eq 'Edit' }).Count | Should -Be 1
    }
}
