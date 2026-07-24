function Invoke-ExecSetLibraryInheritance {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        Sharepoint.Site.ReadWrite
    .DESCRIPTION
        Controls whether a document library inherits its permissions from the site, via the
        SharePoint REST API.

        Action 'Break' detaches the library so it holds its own permissions. CopyRoleAssignments
        (default true) copies the permissions it currently inherits, so nobody loses access at the
        moment of the break; with it disabled the library starts with an empty permission set and
        only site collection admins can reach it. ClearSubscopes (default false) resets any folder
        or item inside the library that has its own unique permissions.

        Action 'Reset' puts the library back to inheriting from the site. This discards every
        permission unique to the library and cannot be undone other than by granting them again.
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $APIName = $Request.Params.CIPPEndpoint
    $Headers = $Request.Headers
    $TenantFilter = $Request.Body.tenantFilter
    $SiteUrl = $Request.Body.SiteUrl
    $ListId = $Request.Body.ListId
    $LibraryName = $Request.Body.LibraryName
    $Action = $Request.Body.Action
    # Default to the safe options: keep current access on a break, leave sub-scopes alone.
    $CopyRoleAssignments = ($Request.Body.CopyRoleAssignments ?? $true) -eq $true
    $ClearSubscopes = $Request.Body.ClearSubscopes -eq $true

    try {
        if ([string]::IsNullOrWhiteSpace($SiteUrl)) { throw 'SiteUrl is required.' }
        if ([string]::IsNullOrWhiteSpace($ListId)) { throw 'ListId is required: a site root web always holds its own permissions.' }
        if ([string]$Action -notin @('Break', 'Reset')) { throw "Action must be 'Break' or 'Reset'." }

        $SPScope = Resolve-CIPPSharePointPermissionScope -SiteUrl $SiteUrl -ListId $ListId -TenantFilter $TenantFilter
        $TargetLabel = if ($LibraryName) { "library $LibraryName" } else { $SPScope.TargetLabel }

        if ($Action -eq 'Break') {
            if ($SPScope.HasUniqueRoleAssignments) {
                $Result = "$TargetLabel already has its own permissions; nothing to change."
            } else {
                $null = New-GraphPostRequest -uri "$($SPScope.ScopeUri)/breakroleinheritance(copyRoleAssignments=$($CopyRoleAssignments.ToString().ToLower()),clearSubscopes=$($ClearSubscopes.ToString().ToLower()))" -tenantid $TenantFilter -scope $SPScope.Scope -type POST -body '{}' -AddedHeaders $SPScope.Headers -UseCertificate -AsApp $true
                $Detail = if ($CopyRoleAssignments) {
                    'The permissions it inherited were copied across, so current access is unchanged.'
                } else {
                    'It started with an empty permission set, so only site collection admins can reach it until permissions are granted.'
                }
                if ($ClearSubscopes) { $Detail += ' Unique permissions on folders and items inside it were reset.' }
                $Result = "Successfully stopped $TargetLabel inheriting permissions from the site. $Detail"
            }
        } else {
            if (-not $SPScope.HasUniqueRoleAssignments) {
                $Result = "$TargetLabel already inherits its permissions from the site; nothing to change."
            } else {
                $null = New-GraphPostRequest -uri "$($SPScope.ScopeUri)/resetroleinheritance" -tenantid $TenantFilter -scope $SPScope.Scope -type POST -body '{}' -AddedHeaders $SPScope.Headers -UseCertificate -AsApp $true
                $Result = "Successfully restored permission inheritance on $TargetLabel. The permissions that were unique to it have been discarded and it now follows the site."
            }
        }

        Write-LogMessage -Headers $Headers -API $APIName -tenant $TenantFilter -message $Result -sev Info
        $StatusCode = [HttpStatusCode]::OK
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        $FailTarget = if ($LibraryName) { "library $LibraryName" } else { 'the library' }
        $Result = "Failed to change permission inheritance on $FailTarget. Error: $($ErrorMessage.NormalizedError)"
        Write-LogMessage -Headers $Headers -API $APIName -tenant $TenantFilter -message $Result -sev Error -LogData $ErrorMessage
        $StatusCode = [HttpStatusCode]::BadRequest
    }

    return ([HttpResponseContext]@{
            StatusCode = $StatusCode
            Body       = @{'Results' = $Result }
        })
}
