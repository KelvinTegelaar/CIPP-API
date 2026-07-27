function Invoke-ExecSetLibraryPermission {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        Sharepoint.Site.ReadWrite
    .DESCRIPTION
        Grants users and/or groups a SharePoint permission level on a document library (ListId) or
        on the site root web (ListId omitted) via the SharePoint REST API. Principals are resolved
        with ensureuser unless PrincipalId is supplied, role inheritance on the library is broken
        (copying the existing permissions) when it still inherits, and the role assignment is added
        with addroleassignment.

        Mode 'Add' leaves any level the principal already holds in place - SharePoint allows a
        principal to hold several at once. Mode 'Replace' removes the levels it already holds on
        this scope first, so the principal ends up with exactly the requested one.

        The level is taken from RoleDefinitionId when supplied (which is how custom permission
        levels are addressed), otherwise from the named PermissionLevel.
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $APIName = $Request.Params.CIPPEndpoint
    $Headers = $Request.Headers
    $TenantFilter = $Request.Body.tenantFilter
    $SiteUrl = $Request.Body.SiteUrl
    $ListId = $Request.Body.ListId
    $LibraryName = $Request.Body.LibraryName
    $PermissionLevel = $Request.Body.PermissionLevel
    $RoleDefinitionId = $Request.Body.RoleDefinitionId
    $PrincipalId = $Request.Body.PrincipalId
    $PrincipalName = $Request.Body.PrincipalName
    $Mode = $Request.Body.Mode ?? 'Add'
    $Users = @($Request.Body.Users)
    $Groups = @($Request.Body.Groups)

    # Built-in SharePoint role definition IDs, used when the caller names a level instead of
    # supplying a role definition id.
    $RoleDefinitionIds = @{
        'read'        = 1073741826
        'contribute'  = 1073741827
        'design'      = 1073741828
        'fullControl' = 1073741829
        'edit'        = 1073741830
    }

    try {
        if ([string]::IsNullOrWhiteSpace($SiteUrl)) { throw 'SiteUrl is required.' }

        $RoleDefId = if (-not [string]::IsNullOrWhiteSpace($RoleDefinitionId)) {
            $RoleDefinitionId
        } else {
            $RoleDefinitionIds[[string]$PermissionLevel]
        }
        if (-not $RoleDefId) { throw 'No permission level was selected.' }

        # Build the claims-encoded logon names for ensureuser. A PrincipalId from the permission
        # list is already resolved on the site, so it skips that round-trip.
        $Principals = [System.Collections.Generic.List[object]]::new()
        if (-not [string]::IsNullOrWhiteSpace($PrincipalId)) {
            $Principals.Add([PSCustomObject]@{
                    Id        = $PrincipalId
                    LogonName = $null
                    Label     = "$($PrincipalName ?? $PrincipalId)"
                    IsGroup   = $false
                })
        }
        foreach ($User in $Users) {
            if ($null -eq $User -or -not $User.value) { continue }
            $Principals.Add([PSCustomObject]@{
                    Id        = $null
                    LogonName = "i:0#.f|membership|$($User.value)"
                    Label     = "$($User.value)"
                    IsGroup   = $false
                })
        }
        foreach ($Group in $Groups) {
            if ($null -eq $Group -or -not $Group.value) { continue }
            # Microsoft 365 groups use the federated directory claim; security groups the tenant claim.
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
        if ($Principals.Count -eq 0) {
            throw 'No users or groups selected.'
        }

        # Resolving with -EnsureUniqueRoleAssignments breaks inheritance (copying the existing
        # permissions) when a library still inherits, so the grant stays scoped to the library.
        $SPScope = Resolve-CIPPSharePointPermissionScope -SiteUrl $SiteUrl -ListId $ListId -TenantFilter $TenantFilter -EnsureUniqueRoleAssignments

        # Replace needs the levels each principal currently holds so they can be removed first.
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
                    $EnsuredUser = New-GraphPostRequest -uri "$($SPScope.BaseUri)/web/ensureuser" -tenantid $TenantFilter -scope $SPScope.Scope -type POST -body $EnsureBody -AddedHeaders $SPScope.Headers -UseCertificate -AsApp $true
                    if (-not $EnsuredUser.Id) {
                        throw 'Could not resolve principal on the site.'
                    }
                    $ResolvedId = $EnsuredUser.Id
                }

                if ($Mode -eq 'Replace') {
                    # Drop every level this principal already holds here, except Limited Access
                    # (RoleTypeKind 1) which SharePoint maintains itself.
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
                # SharePoint returns an OData JSON envelope; translate it rather than passing it on.
                $Failed.Add("$($Principal.Label) - $(Get-CIPPSharePointErrorMessage -ErrorMessage $_.Exception.Message -IsGroup:$Principal.IsGroup)")
            }
        }

        # Named levels have a fixed label; a role definition id is looked up on the site so
        # custom levels are logged under their real name.
        $LevelLabel = if ($PermissionLevel) {
            switch ([string]$PermissionLevel) {
                'fullControl' { 'Full Control' }
                default { (Get-Culture).TextInfo.ToTitleCase([string]$PermissionLevel) }
            }
        } else {
            try {
                (New-GraphGetRequest -uri "$($SPScope.BaseUri)/web/roledefinitions/getbyid($RoleDefId)?`$select=Name" -tenantid $TenantFilter -scope $SPScope.Scope -extraHeaders $SPScope.Headers -UseCertificate -AsApp $true).Name
            } catch {
                "role definition $RoleDefId"
            }
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
            # The explanations are already sentences, so trim before adding the closing period.
            $Messages.Add("Failed for $(($Failed -join '; ').TrimEnd('.')).")
        }
        $Result = $Messages -join ' '
        if ($Granted.Count -gt 0) {
            Write-LogMessage -Headers $Headers -API $APIName -tenant $TenantFilter -message $Result -sev Info
            $StatusCode = [HttpStatusCode]::OK
        } else {
            Write-LogMessage -Headers $Headers -API $APIName -tenant $TenantFilter -message $Result -sev Error
            $StatusCode = [HttpStatusCode]::BadRequest
        }
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        $FailTarget = if ($LibraryName) { "library $LibraryName" } else { 'the site root' }
        $Result = "Failed to set permission on $FailTarget. Error: $($ErrorMessage.NormalizedError)"
        Write-LogMessage -Headers $Headers -API $APIName -tenant $TenantFilter -message $Result -sev Error -LogData $ErrorMessage
        $StatusCode = [HttpStatusCode]::BadRequest
    }

    return ([HttpResponseContext]@{
            StatusCode = $StatusCode
            Body       = @{'Results' = $Result }
        })
}
