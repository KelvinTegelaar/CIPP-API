function Invoke-ListSitePermissions {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        Sharepoint.Site.Read
    .DESCRIPTION
        Lists the permissions of a SharePoint scope via the SharePoint REST API with certificate
        authentication: the inheritance state plus every role assignment, flattened to one row per
        principal and permission level. Supplying ListId targets a document library; omitting it
        targets the site root web. Limited Access assignments are returned but flagged as system
        managed - SharePoint creates them automatically so a user can traverse to an item they were
        given access to, and removing them by hand breaks that navigation.
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $APIName = $Request.Params.CIPPEndpoint
    $TenantFilter = $Request.Query.tenantFilter ?? $Request.Body.tenantFilter
    $SiteUrl = $Request.Query.SiteUrl ?? $Request.Body.SiteUrl
    $ListId = $Request.Query.ListId ?? $Request.Body.ListId

    # A SharePoint principal is a guest/external identity when either guest flag is set or the
    # claims login carries the external-user or spo-guest marker.
    function Test-SPGuestPrincipal($Principal) {
        [bool]$Principal.IsShareByEmailGuestUser -or [bool]$Principal.IsEmailAuthenticationGuestUser -or $Principal.LoginName -match '(?i)#ext#|urn%3aspo%3aguest'
    }

    try {
        if ([string]::IsNullOrWhiteSpace($SiteUrl)) { throw 'SiteUrl is required.' }

        $SharePointInfo = Get-SharePointAdminLink -Public $false -tenantFilter $TenantFilter
        $Scope = "$($SharePointInfo.SharePointUrl)/.default"
        $JsonAccept = @{ Accept = 'application/json;odata=nometadata' }
        $BaseUri = "$($SiteUrl.TrimEnd('/'))/_api"

        # Scope: a document library, or the site root web when no list was supplied.
        $IsLibrary = -not [string]::IsNullOrWhiteSpace($ListId)
        if ($IsLibrary) {
            $ScopeUri = "$BaseUri/web/lists(guid'$ListId')"
            $ListInfo = New-GraphGetRequest -uri "$ScopeUri`?`$select=HasUniqueRoleAssignments,Title" -tenantid $TenantFilter -scope $Scope -extraHeaders $JsonAccept -UseCertificate -AsApp $true
            $HasUniqueRoleAssignments = [bool]$ListInfo.HasUniqueRoleAssignments
            $TargetTitle = $ListInfo.Title
            $TargetType = 'Library'
        } else {
            $ScopeUri = "$BaseUri/web"
            $WebInfo = New-GraphGetRequest -uri "$ScopeUri`?`$select=HasUniqueRoleAssignments,Title" -tenantid $TenantFilter -scope $Scope -extraHeaders $JsonAccept -UseCertificate -AsApp $true
            # A site collection root web always holds its own assignments.
            $HasUniqueRoleAssignments = $true
            $TargetTitle = $WebInfo.Title
            $TargetType = 'Site'
        }

        $Assignments = @(New-GraphGetRequest -uri "$ScopeUri/roleassignments?`$expand=Member,RoleDefinitionBindings" -tenantid $TenantFilter -scope $Scope -extraHeaders $JsonAccept -UseCertificate -AsApp $true)

        # One row per principal and permission level: SharePoint allows a principal to hold
        # several levels on the same scope, and each is removed separately.
        $Results = [System.Collections.Generic.List[object]]::new()
        foreach ($Assignment in $Assignments) {
            $Member = $Assignment.Member
            if (-not $Member) { continue }
            $PrincipalType = switch ($Member.PrincipalType) {
                1 { 'User' }
                4 { 'Security Group' }
                8 { 'SharePoint Group' }
                default { 'Other' }
            }
            foreach ($Binding in @($Assignment.RoleDefinitionBindings)) {
                $Results.Add([PSCustomObject]@{
                        PrincipalId       = [string]$Member.Id
                        Title             = $Member.Title
                        LoginName         = $Member.LoginName
                        Email             = $Member.Email
                        UserPrincipalName = if ($Member.PrincipalType -eq 1 -and $Member.LoginName) { ($Member.LoginName -split '\|')[-1] } else { $null }
                        PrincipalType     = $PrincipalType
                        IsGuest           = (Test-SPGuestPrincipal $Member)
                        PermissionLevel   = $Binding.Name
                        RoleDefinitionId  = [string]$Binding.Id
                        # RoleTypeKind 1 is Limited Access: created and cleaned up by SharePoint itself.
                        IsSystemManaged   = ($Binding.RoleTypeKind -eq 1)
                    })
            }
        }

        $Body = [PSCustomObject]@{
            HasUniqueRoleAssignments = $HasUniqueRoleAssignments
            TargetTitle              = $TargetTitle
            TargetType               = $TargetType
            Assignments              = @($Results)
        }
        $StatusCode = [HttpStatusCode]::OK
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        $Body = "Failed to list permissions: $($ErrorMessage.NormalizedError)"
        Write-LogMessage -Headers $Request.Headers -API $APIName -tenant $TenantFilter -message $Body -sev Error -LogData $ErrorMessage
        $StatusCode = [HttpStatusCode]::BadRequest
    }

    return ([HttpResponseContext]@{
            StatusCode = $StatusCode
            Body       = @{ 'Results' = $Body }
        })
}
