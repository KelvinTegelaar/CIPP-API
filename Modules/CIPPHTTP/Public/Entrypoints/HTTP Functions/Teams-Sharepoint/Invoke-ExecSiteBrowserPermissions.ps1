function Invoke-ExecSiteBrowserPermissions {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        Sharepoint.Site.ReadWrite
    .DESCRIPTION
        Mutating actions for the SharePoint site browser permissions dialog.
        Body.Action selects the operation. SiteUrl + tenantFilter are always required.
        ListId scopes library actions; omit it for the site root web.
        Sharing links / Graph drive permissions are out of scope.
        Graph site permissions (Sites.Selected app grants): RemoveGraphSitePermission.
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $APIName = $Request.Params.CIPPEndpoint
    $Headers = $Request.Headers
    $TenantFilter = $Request.Body.tenantFilter ?? $Request.Body.TenantFilter
    $SiteUrl = $Request.Body.SiteUrl
    $SiteId = $Request.Body.SiteId
    $ListId = $Request.Body.ListId
    $LibraryName = $Request.Body.LibraryName
    $Action = $Request.Body.Action

    $BuiltInRoleDefinitionIds = @{
        'read'        = 1073741826
        'contribute'  = 1073741827
        'design'      = 1073741828
        'fullControl' = 1073741829
        'edit'        = 1073741830
    }

    function Resolve-BrowserPermissionRoleDefId {
        param($PermissionLevel, $RoleDefinitionId)
        if (-not [string]::IsNullOrWhiteSpace($RoleDefinitionId)) {
            if ($RoleDefinitionId -is [PSCustomObject] -and $RoleDefinitionId.value) {
                return [string]$RoleDefinitionId.value
            }
            return [string]$RoleDefinitionId
        }
        $Key = [string]$PermissionLevel
        if ($PermissionLevel -is [PSCustomObject] -and $PermissionLevel.value) {
            $Key = [string]$PermissionLevel.value
        }
        return $BuiltInRoleDefinitionIds[$Key]
    }

    function ConvertTo-BrowserPermissionPrincipals {
        param(
            $PrincipalId,
            $PrincipalName,
            $Users,
            $Groups
        )
        $Principals = [System.Collections.Generic.List[object]]::new()
        if (-not [string]::IsNullOrWhiteSpace($PrincipalId)) {
            $Principals.Add([PSCustomObject]@{
                    Id        = $PrincipalId
                    LogonName = $null
                    Label     = "$($PrincipalName ?? $PrincipalId)"
                    IsGroup   = $false
                })
        }
        foreach ($User in @($Users)) {
            if ($null -eq $User -or -not $User.value) { continue }
            $Principals.Add([PSCustomObject]@{
                    Id        = $null
                    LogonName = "i:0#.f|membership|$($User.value)"
                    Label     = "$($User.value)"
                    IsGroup   = $false
                })
        }
        foreach ($Group in @($Groups)) {
            if ($null -eq $Group -or -not $Group.value) { continue }
            $IsUnified = @($Group.addedFields.groupTypes) -contains 'Unified'
            $LogonName = if ($IsUnified) {
                "c:0o.c|federateddirectoryclaimprovider|$($Group.value)"
            } else {
                "c:0t.c|tenant|$($Group.value)"
            }
            $Principals.Add([PSCustomObject]@{
                    Id        = $null
                    LogonName = $LogonName
                    Label     = "$($Group.label ?? $Group.value)"
                    IsGroup   = $true
                })
        }
        return $Principals
    }

    function Invoke-BrowserGrantAccess {
        param($Mode = 'Add')

        $RoleDefId = Resolve-BrowserPermissionRoleDefId -PermissionLevel $Request.Body.PermissionLevel -RoleDefinitionId $Request.Body.RoleDefinitionId
        if (-not $RoleDefId) { throw 'No permission level was selected.' }

        $Principals = ConvertTo-BrowserPermissionPrincipals `
            -PrincipalId $Request.Body.PrincipalId `
            -PrincipalName $Request.Body.PrincipalName `
            -Users $Request.Body.Users `
            -Groups $Request.Body.Groups
        if ($Principals.Count -eq 0) { throw 'No users or groups selected.' }

        $SPScope = Resolve-CIPPSharePointPermissionScope -SiteUrl $SiteUrl -ListId $ListId -TenantFilter $TenantFilter -EnsureUniqueRoleAssignments

        $ExistingAssignments = @()
        if ($Mode -eq 'Replace') {
            $ExistingAssignments = @(New-GraphGetRequest -uri "$($SPScope.AssignmentUri)?`$expand=Member,RoleDefinitionBindings" -tenantid $TenantFilter -scope $SPScope.Scope -extraHeaders $SPScope.Headers -UseCertificate -AsApp $true)
        }

        $Granted = [System.Collections.Generic.List[string]]::new()
        $Failed = [System.Collections.Generic.List[string]]::new()
        foreach ($Principal in $Principals) {
            try {
                $ResolvedId = $Principal.Id
                if (-not $ResolvedId) {
                    $EnsureBody = ConvertTo-Json -Compress -InputObject @{ logonName = $Principal.LogonName }
                    $Ensured = New-GraphPostRequest -uri "$($SPScope.BaseUri)/web/ensureuser" -tenantid $TenantFilter -scope $SPScope.Scope -type POST -body $EnsureBody -AddedHeaders $SPScope.Headers -UseCertificate -AsApp $true
                    if (-not $Ensured.Id) { throw 'Could not resolve principal on the site.' }
                    $ResolvedId = $Ensured.Id
                }

                if ($Mode -eq 'Replace') {
                    $Current = @($ExistingAssignments | Where-Object { [string]$_.Member.Id -eq [string]$ResolvedId })
                    foreach ($Assignment in $Current) {
                        foreach ($Binding in @($Assignment.RoleDefinitionBindings)) {
                            if ($Binding.RoleTypeKind -eq 1) { continue }
                            if ([string]$Binding.Id -eq [string]$RoleDefId) { continue }
                            $null = New-GraphPostRequest -uri "$($SPScope.AssignmentUri)/removeroleassignment(principalid=$ResolvedId,roledefid=$($Binding.Id))" -tenantid $TenantFilter -scope $SPScope.Scope -type POST -body '{}' -AddedHeaders $SPScope.Headers -UseCertificate -AsApp $true
                        }
                    }
                }

                $null = New-GraphPostRequest -uri "$($SPScope.AssignmentUri)/addroleassignment(principalid=$ResolvedId,roledefid=$RoleDefId)" -tenantid $TenantFilter -scope $SPScope.Scope -type POST -body '{}' -AddedHeaders $SPScope.Headers -UseCertificate -AsApp $true
                $Granted.Add($Principal.Label)
            } catch {
                $Failed.Add("$($Principal.Label) - $(Get-CIPPSharePointErrorMessage -ErrorMessage $_.Exception.Message -IsGroup:$Principal.IsGroup)")
            }
        }

        $LevelLabel = if ($Request.Body.PermissionLevel) {
            switch ([string]$Request.Body.PermissionLevel) {
                'fullControl' { 'Full Control' }
                default { (Get-Culture).TextInfo.ToTitleCase([string]$Request.Body.PermissionLevel) }
            }
        } else {
            try {
                (New-GraphGetRequest -uri "$($SPScope.BaseUri)/web/roledefinitions/getbyid($RoleDefId)?`$select=Name" -tenantid $TenantFilter -scope $SPScope.Scope -extraHeaders $SPScope.Headers -UseCertificate -AsApp $true).Name
            } catch { "role definition $RoleDefId" }
        }
        $TargetLabel = if ($LibraryName) { "library $LibraryName" } else { $SPScope.TargetLabel }
        $Verb = if ($Mode -eq 'Replace') { 'set' } else { 'granted' }

        $Messages = [System.Collections.Generic.List[string]]::new()
        if ($Granted.Count -gt 0) {
            $Messages.Add("Successfully $Verb $LevelLabel on $TargetLabel for $($Granted -join ', ').")
        }
        if ($SPScope.BrokeInheritance) {
            $Messages.Add('Permission inheritance was broken so the change applies to this library only; the permissions it inherited were copied across.')
        }
        if ($Failed.Count -gt 0) {
            $Messages.Add("Failed for $(($Failed -join '; ').TrimEnd('.')).")
        }
        $Result = $Messages -join ' '
        if ($Granted.Count -eq 0) { throw $Result }
        return $Result
    }

    function Invoke-BrowserRemoveAccess {
        $PrincipalId = $Request.Body.PrincipalId
        $RoleDefinitionId = $Request.Body.RoleDefinitionId
        $Label = $Request.Body.PrincipalName ?? $Request.Body.Title ?? $PrincipalId
        if ([string]::IsNullOrWhiteSpace($PrincipalId)) { throw 'PrincipalId is required.' }

        $SPScope = Resolve-CIPPSharePointPermissionScope -SiteUrl $SiteUrl -ListId $ListId -TenantFilter $TenantFilter -EnsureUniqueRoleAssignments
        $Assignments = @(New-GraphGetRequest -uri "$($SPScope.AssignmentUri)?`$expand=Member,RoleDefinitionBindings" -tenantid $TenantFilter -scope $SPScope.Scope -extraHeaders $SPScope.Headers -UseCertificate -AsApp $true)
        $Current = @($Assignments | Where-Object { [string]$_.Member.Id -eq [string]$PrincipalId })
        if ($Current.Count -eq 0) {
            throw "$Label holds no permissions on $($SPScope.TargetLabel)."
        }
        if (-not $Label -or $Label -eq $PrincipalId) { $Label = $Current[0].Member.Title ?? $PrincipalId }

        $Targets = [System.Collections.Generic.List[object]]::new()
        $SkippedSystem = [System.Collections.Generic.List[string]]::new()
        foreach ($Assignment in $Current) {
            foreach ($Binding in @($Assignment.RoleDefinitionBindings)) {
                if (-not [string]::IsNullOrWhiteSpace($RoleDefinitionId) -and [string]$Binding.Id -ne [string]$RoleDefinitionId) { continue }
                if ($Binding.RoleTypeKind -eq 1) {
                    $SkippedSystem.Add($Binding.Name)
                    continue
                }
                $Targets.Add($Binding)
            }
        }

        if ($Targets.Count -eq 0) {
            if ($SkippedSystem.Count -gt 0) {
                throw "$Label only holds $($SkippedSystem -join ', ') on $($SPScope.TargetLabel). SharePoint manages that level itself and it cannot be removed here."
            }
            throw "No matching permission found for $Label on $($SPScope.TargetLabel)."
        }

        $Removed = [System.Collections.Generic.List[string]]::new()
        $Failed = [System.Collections.Generic.List[string]]::new()
        foreach ($Binding in $Targets) {
            try {
                $null = New-GraphPostRequest -uri "$($SPScope.AssignmentUri)/removeroleassignment(principalid=$PrincipalId,roledefid=$($Binding.Id))" -tenantid $TenantFilter -scope $SPScope.Scope -type POST -body '{}' -AddedHeaders $SPScope.Headers -UseCertificate -AsApp $true
                $Removed.Add($Binding.Name)
            } catch {
                $Failed.Add("$($Binding.Name) - $(Get-CIPPSharePointErrorMessage -ErrorMessage $_.Exception.Message)")
            }
        }

        $TargetLabel = if ($LibraryName) { "library $LibraryName" } else { $SPScope.TargetLabel }
        $Messages = [System.Collections.Generic.List[string]]::new()
        if ($Removed.Count -gt 0) {
            $Messages.Add("Successfully removed $($Removed -join ', ') from $Label on $TargetLabel.")
        }
        if ($SPScope.BrokeInheritance) {
            $Messages.Add('Permission inheritance was broken so the change applies to this library only; the permissions it inherited were copied across.')
        }
        if ($Failed.Count -gt 0) {
            $Messages.Add("Failed for $(($Failed -join '; ').TrimEnd('.')).")
        }
        $Result = $Messages -join ' '
        if ($Removed.Count -eq 0) { throw $Result }
        return $Result
    }

    function Invoke-BrowserGroupMembership {
        param([bool]$Add)

        $GroupId = $Request.Body.GroupId
        if ([string]::IsNullOrWhiteSpace($GroupId)) { throw 'GroupId is required.' }

        $SharePointInfo = Get-SharePointAdminLink -Public $false -tenantFilter $TenantFilter
        $Scope = "$($SharePointInfo.SharePointUrl)/.default"
        $JsonAccept = @{ Accept = 'application/json;odata=nometadata' }
        $BaseUri = "$($SiteUrl.TrimEnd('/'))/_api"

        $Principals = ConvertTo-BrowserPermissionPrincipals `
            -PrincipalId $Request.Body.PrincipalId `
            -PrincipalName $Request.Body.PrincipalName `
            -Users $Request.Body.Users `
            -Groups $Request.Body.Groups
        if ($Principals.Count -eq 0) { throw 'No users or groups selected.' }

        $Done = [System.Collections.Generic.List[string]]::new()
        $Failed = [System.Collections.Generic.List[string]]::new()
        foreach ($Principal in $Principals) {
            try {
                $ResolvedId = $Principal.Id
                $LoginName = $null
                if (-not $ResolvedId) {
                    $EnsureBody = ConvertTo-Json -Compress -InputObject @{ logonName = $Principal.LogonName }
                    $Ensured = New-GraphPostRequest -uri "$BaseUri/web/ensureuser" -tenantid $TenantFilter -scope $Scope -type POST -body $EnsureBody -contentType 'application/json;odata=nometadata' -AddedHeaders $JsonAccept -UseCertificate -AsApp $true
                    if (-not $Ensured.Id) { throw 'Could not resolve principal on the site.' }
                    $ResolvedId = $Ensured.Id
                    $LoginName = $Ensured.LoginName
                } elseif ($Principal.LogonName) {
                    $LoginName = $Principal.LogonName
                } else {
                    $Existing = New-GraphGetRequest -uri "$BaseUri/web/getuserbyid($ResolvedId)?`$select=Id,LoginName,Title" -tenantid $TenantFilter -scope $Scope -extraHeaders $JsonAccept -UseCertificate -AsApp $true
                    $LoginName = $Existing.LoginName
                }

                if ($Add) {
                    $AddBody = ConvertTo-Json -Compress -Depth 5 -InputObject @{
                        '__metadata' = @{ 'type' = 'SP.User' }
                        'LoginName'  = $LoginName
                    }
                    $null = New-GraphPostRequest -uri "$BaseUri/web/sitegroups($GroupId)/users" -tenantid $TenantFilter -scope $Scope -type POST -body $AddBody -contentType 'application/json;odata=verbose' -AddedHeaders $JsonAccept -UseCertificate -AsApp $true
                } else {
                    $null = New-GraphPostRequest -uri "$BaseUri/web/sitegroups($GroupId)/users/removebyid($ResolvedId)" -tenantid $TenantFilter -scope $Scope -type POST -body '{}' -contentType 'application/json;odata=nometadata' -AddedHeaders $JsonAccept -UseCertificate -AsApp $true
                }
                $Done.Add($Principal.Label)
            } catch {
                $Failed.Add("$($Principal.Label) - $(Get-CIPPSharePointErrorMessage -ErrorMessage $_.Exception.Message -IsGroup:$Principal.IsGroup)")
            }
        }

        $Verb = if ($Add) { 'added to' } else { 'removed from' }
        $GroupLabel = $Request.Body.GroupName ?? "group $GroupId"
        $Messages = [System.Collections.Generic.List[string]]::new()
        if ($Done.Count -gt 0) {
            $Messages.Add("Successfully $Verb $GroupLabel`: $($Done -join ', ').")
        }
        if ($Failed.Count -gt 0) {
            $Messages.Add("Failed for $(($Failed -join '; ').TrimEnd('.')).")
        }
        $Result = $Messages -join ' '
        if ($Done.Count -eq 0) { throw $Result }
        return $Result
    }

    function Invoke-BrowserSiteAdmin {
        param([bool]$Add)

        $Users = @($Request.Body.Users)
        $UPNs = foreach ($User in $Users) {
            if ($User -is [string] -and $User) { $User }
            elseif ($User.value) { $User.value }
        }
        $UPNs = @($UPNs | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
        if ($UPNs.Count -eq 0 -and $Request.Body.PrincipalName) {
            # Allow a single login/UPN from a selected admin row.
            $Candidate = $Request.Body.userPrincipalName ?? $Request.Body.PrincipalName
            if ($Candidate -match '@') { $UPNs = @($Candidate) }
        }
        if ($UPNs.Count -eq 0) { throw 'No users selected.' }

        $Results = Set-CIPPSharePointPerms -tenantFilter $TenantFilter -OnedriveAccessUser $UPNs -URL $SiteUrl -Headers $Headers -APIName $APIName -RemovePermission:(-not $Add)
        return (@($Results) -join ' ')
    }

    function Invoke-BrowserInheritance {
        param([ValidateSet('Break', 'Reset')][string]$Mode)

        if ([string]::IsNullOrWhiteSpace($ListId)) {
            throw 'ListId is required: a site root web always holds its own permissions.'
        }
        $CopyRoleAssignments = ($Request.Body.CopyRoleAssignments ?? $true) -eq $true
        $ClearSubscopes = $Request.Body.ClearSubscopes -eq $true

        $SPScope = Resolve-CIPPSharePointPermissionScope -SiteUrl $SiteUrl -ListId $ListId -TenantFilter $TenantFilter
        $TargetLabel = if ($LibraryName) { "library $LibraryName" } else { $SPScope.TargetLabel }

        if ($Mode -eq 'Break') {
            if ($SPScope.HasUniqueRoleAssignments) {
                return "$TargetLabel already has its own permissions; nothing to change."
            }
            $null = New-GraphPostRequest -uri "$($SPScope.ScopeUri)/breakroleinheritance(copyRoleAssignments=$($CopyRoleAssignments.ToString().ToLower()),clearSubscopes=$($ClearSubscopes.ToString().ToLower()))" -tenantid $TenantFilter -scope $SPScope.Scope -type POST -body '{}' -AddedHeaders $SPScope.Headers -UseCertificate -AsApp $true
            $Detail = if ($CopyRoleAssignments) {
                'The permissions it inherited were copied across, so current access is unchanged.'
            } else {
                'It started with an empty permission set, so only site collection admins can reach it until permissions are granted.'
            }
            if ($ClearSubscopes) { $Detail += ' Unique permissions on folders and items inside it were reset.' }
            return "Successfully stopped $TargetLabel inheriting permissions from the site. $Detail"
        }

        if (-not $SPScope.HasUniqueRoleAssignments) {
            return "$TargetLabel already inherits its permissions from the site; nothing to change."
        }
        $null = New-GraphPostRequest -uri "$($SPScope.ScopeUri)/resetroleinheritance" -tenantid $TenantFilter -scope $SPScope.Scope -type POST -body '{}' -AddedHeaders $SPScope.Headers -UseCertificate -AsApp $true
        return "Successfully restored permission inheritance on $TargetLabel. The permissions that were unique to it have been discarded and it now follows the site."
    }

    function Invoke-BrowserRemoveGraphSitePermission {
        $PermissionId = $Request.Body.PermissionId
        if ([string]::IsNullOrWhiteSpace($PermissionId)) { throw 'PermissionId is required.' }

        $ResolvedSiteId = $SiteId
        if ([string]::IsNullOrWhiteSpace($ResolvedSiteId)) {
            $ParsedUrl = [System.Uri]$SiteUrl
            $SiteSegment = if ($ParsedUrl.AbsolutePath -in @('', '/')) {
                $ParsedUrl.Host
            } else {
                "$($ParsedUrl.Host):$($ParsedUrl.AbsolutePath):"
            }
            $SiteMeta = New-GraphGetRequest -uri "https://graph.microsoft.com/v1.0/sites/$SiteSegment`?`$select=id" -tenantid $TenantFilter -asapp $true
            $ResolvedSiteId = $SiteMeta.id
        }
        if ([string]::IsNullOrWhiteSpace($ResolvedSiteId)) { throw 'Could not resolve Graph site id.' }

        $null = New-GraphPostRequest -uri "https://graph.microsoft.com/v1.0/sites/$ResolvedSiteId/permissions/$PermissionId" -tenantid $TenantFilter -type DELETE -asapp $true
        $Label = $Request.Body.PrincipalName ?? $PermissionId
        return "Successfully removed Graph site permission for $Label."
    }

    try {
        if ([string]::IsNullOrWhiteSpace($TenantFilter)) { throw 'tenantFilter is required.' }
        if ([string]::IsNullOrWhiteSpace($SiteUrl)) { throw 'SiteUrl is required.' }
        if ([string]::IsNullOrWhiteSpace($Action)) { throw 'Action is required.' }

        $Result = switch ([string]$Action) {
            'GrantAccess' { Invoke-BrowserGrantAccess -Mode 'Add' }
            'ReplaceAccess' { Invoke-BrowserGrantAccess -Mode 'Replace' }
            'RemoveAccess' { Invoke-BrowserRemoveAccess }
            'AddGroupMember' { Invoke-BrowserGroupMembership -Add $true }
            'RemoveGroupMember' { Invoke-BrowserGroupMembership -Add $false }
            'AddSiteAdmin' { Invoke-BrowserSiteAdmin -Add $true }
            'RemoveSiteAdmin' { Invoke-BrowserSiteAdmin -Add $false }
            'BreakInheritance' { Invoke-BrowserInheritance -Mode 'Break' }
            'RestoreInheritance' { Invoke-BrowserInheritance -Mode 'Reset' }
            'RemoveGraphSitePermission' { Invoke-BrowserRemoveGraphSitePermission }
            default {
                throw "Unknown Action '$Action'. Supported: GrantAccess, ReplaceAccess, RemoveAccess, AddGroupMember, RemoveGroupMember, AddSiteAdmin, RemoveSiteAdmin, BreakInheritance, RestoreInheritance, RemoveGraphSitePermission."
            }
        }

        Write-LogMessage -Headers $Headers -API $APIName -tenant $TenantFilter -message $Result -sev Info
        $StatusCode = [HttpStatusCode]::OK
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        $Result = "Failed to run Action '$Action'. Error: $($ErrorMessage.NormalizedError)"
        Write-LogMessage -Headers $Headers -API $APIName -tenant $TenantFilter -message $Result -sev Error -LogData $ErrorMessage
        $StatusCode = [HttpStatusCode]::BadRequest
    }

    return ([HttpResponseContext]@{
            StatusCode = $StatusCode
            Body       = @{'Results' = $Result }
        })
}
