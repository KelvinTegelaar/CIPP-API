function Invoke-ExecRemoveLibraryPermission {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        Sharepoint.Site.ReadWrite
    .DESCRIPTION
        Removes a principal's permission on a document library (ListId) or on the site root web
        (ListId omitted) via the SharePoint REST API. Supplying RoleDefinitionId removes that one
        permission level; omitting it removes every level the principal holds on the scope.

        Limited Access is never removed: SharePoint creates and cleans it up itself so a user can
        traverse to an item they were given access to further down, and deleting it by hand breaks
        that navigation.

        Removing a permission requires the library to hold its own permissions, so a library that
        still inherits has its inheritance broken (copying the current permissions) first - the
        removal then applies to that library only, not to the whole site.
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $APIName = $Request.Params.CIPPEndpoint
    $Headers = $Request.Headers
    $TenantFilter = $Request.Body.tenantFilter
    $SiteUrl = $Request.Body.SiteUrl
    $ListId = $Request.Body.ListId
    $LibraryName = $Request.Body.LibraryName
    $PrincipalId = $Request.Body.PrincipalId
    $RoleDefinitionId = $Request.Body.RoleDefinitionId
    $Label = $Request.Body.PrincipalName ?? $Request.Body.Title ?? $PrincipalId

    try {
        if ([string]::IsNullOrWhiteSpace($SiteUrl)) { throw 'SiteUrl is required.' }
        if ([string]::IsNullOrWhiteSpace($PrincipalId)) { throw 'PrincipalId is required.' }

        $SPScope = Resolve-CIPPSharePointPermissionScope -SiteUrl $SiteUrl -ListId $ListId -TenantFilter $TenantFilter -EnsureUniqueRoleAssignments

        # Read what the principal actually holds so only real bindings are removed and Limited
        # Access can be filtered out.
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
                throw "$Label only holds $($SkippedSystem -join ', ') on $($SPScope.TargetLabel). SharePoint manages that level itself and it cannot be removed here; remove the permission that granted it instead."
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
            # The explanations are already sentences, so trim before adding the closing period.
            $Messages.Add("Failed for $(($Failed -join '; ').TrimEnd('.')).")
        }
        $Result = $Messages -join ' '
        if ($Removed.Count -eq 0) { throw $Result }

        Write-LogMessage -Headers $Headers -API $APIName -tenant $TenantFilter -message $Result -sev Info
        $StatusCode = [HttpStatusCode]::OK
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        $Result = "Failed to remove permission for $Label. Error: $($ErrorMessage.NormalizedError)"
        Write-LogMessage -Headers $Headers -API $APIName -tenant $TenantFilter -message $Result -sev Error -LogData $ErrorMessage
        $StatusCode = [HttpStatusCode]::BadRequest
    }

    return ([HttpResponseContext]@{
            StatusCode = $StatusCode
            Body       = @{'Results' = $Result }
        })
}
