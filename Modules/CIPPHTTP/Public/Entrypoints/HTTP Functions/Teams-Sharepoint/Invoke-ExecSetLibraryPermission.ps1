function Invoke-ExecSetLibraryPermission {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        Sharepoint.Site.ReadWrite
    .DESCRIPTION
        Grants users and/or groups a SharePoint permission level (Read, Contribute, Edit, Design
        or Full Control) on a document library via the SharePoint REST API. Principals are
        resolved with ensureuser, role inheritance on the library is broken (copying the
        existing permissions) when it still inherits, and the role assignment is added with
        addroleassignment.
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
    $Users = @($Request.Body.Users)
    $Groups = @($Request.Body.Groups)

    # Standard SharePoint role definition IDs.
    $RoleDefinitionIds = @{
        'read'        = 1073741826
        'contribute'  = 1073741827
        'design'      = 1073741828
        'fullControl' = 1073741829
        'edit'        = 1073741830
    }

    try {
        $RoleDefId = $RoleDefinitionIds[[string]$PermissionLevel]

        # Build the claims-encoded logon names for ensureuser.
        $Principals = [System.Collections.Generic.List[object]]::new()
        foreach ($User in $Users) {
            if ($null -eq $User -or -not $User.value) { continue }
            $Principals.Add([PSCustomObject]@{
                    LogonName = "i:0#.f|membership|$($User.value)"
                    Label     = "$($User.value)"
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
                    LogonName = $LogonName
                    Label     = "$($Group.label ?? $Group.value)"
                })
        }
        if ($Principals.Count -eq 0) {
            throw 'No users or groups selected.'
        }

        $SharePointInfo = Get-SharePointAdminLink -Public $false -tenantFilter $TenantFilter
        $Scope = "$($SharePointInfo.SharePointUrl)/.default"
        $JsonAccept = @{ Accept = 'application/json;odata=nometadata' }
        $BaseUri = "$($SiteUrl.TrimEnd('/'))/_api"

        # Break role inheritance (copying the existing permissions) when the library still inherits.
        $ListInfo = New-GraphGetRequest -uri "$BaseUri/web/lists(guid'$ListId')?`$select=HasUniqueRoleAssignments" -tenantid $TenantFilter -scope $Scope -extraHeaders $JsonAccept -UseCertificate -AsApp $true
        if (-not $ListInfo.HasUniqueRoleAssignments) {
            $null = New-GraphPostRequest -uri "$BaseUri/web/lists(guid'$ListId')/breakroleinheritance(copyRoleAssignments=true,clearSubscopes=false)" -tenantid $TenantFilter -scope $Scope -type POST -body '{}' -AddedHeaders $JsonAccept -UseCertificate -AsApp $true
        }

        $Granted = [System.Collections.Generic.List[string]]::new()
        $Failed = [System.Collections.Generic.List[string]]::new()
        foreach ($Principal in $Principals) {
            try {
                $EnsureBody = ConvertTo-Json -Compress -InputObject @{ logonName = $Principal.LogonName }
                $EnsuredUser = New-GraphPostRequest -uri "$BaseUri/web/ensureuser" -tenantid $TenantFilter -scope $Scope -type POST -body $EnsureBody -AddedHeaders $JsonAccept -UseCertificate -AsApp $true
                if (-not $EnsuredUser.Id) {
                    throw 'Could not resolve principal on the site.'
                }
                $null = New-GraphPostRequest -uri "$BaseUri/web/lists(guid'$ListId')/roleassignments/addroleassignment(principalid=$($EnsuredUser.Id),roledefid=$RoleDefId)" -tenantid $TenantFilter -scope $Scope -type POST -body '{}' -AddedHeaders $JsonAccept -UseCertificate -AsApp $true
                $Granted.Add($Principal.Label)
            } catch {
                $Failed.Add("$($Principal.Label) ($($_.Exception.Message))")
            }
        }

        $LevelLabel = switch ([string]$PermissionLevel) {
            'fullControl' { 'Full Control' }
            default { (Get-Culture).TextInfo.ToTitleCase([string]$PermissionLevel) }
        }
        $Messages = [System.Collections.Generic.List[string]]::new()
        if ($Granted.Count -gt 0) {
            $Messages.Add("Successfully granted $LevelLabel on library $LibraryName to $($Granted -join ', ').")
        }
        if ($Failed.Count -gt 0) {
            $Messages.Add("Failed for $($Failed -join '; ').")
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
        $Result = "Failed to set permission on library $LibraryName. Error: $($ErrorMessage.NormalizedError)"
        Write-LogMessage -Headers $Headers -API $APIName -tenant $TenantFilter -message $Result -sev Error -LogData $ErrorMessage
        $StatusCode = [HttpStatusCode]::BadRequest
    }

    return ([HttpResponseContext]@{
            StatusCode = $StatusCode
            Body       = @{'Results' = $Result }
        })
}
