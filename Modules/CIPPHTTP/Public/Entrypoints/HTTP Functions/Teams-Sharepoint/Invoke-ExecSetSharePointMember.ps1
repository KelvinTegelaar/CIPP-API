function Invoke-ExecSetSharePointMember {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        Sharepoint.Site.ReadWrite
    .DESCRIPTION
        Adds or removes a user in a SharePoint site role (Owners, Members or Visitors).
        Group-connected sites manage Owners/Members through the backing M365 group via Graph;
        Visitors (and classic/communication sites entirely) are managed through the site's
        associated SharePoint role groups via the SharePoint REST API using certificate
        authentication. Removals sourced from ListSiteMembers carry the group and type of the
        selected entry, so users directly added to a role group on a group-connected site are
        removed from that group rather than from the M365 group.
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $APIName = $Request.Params.CIPPEndpoint
    $Headers = $Request.Headers
    $TenantFilter = $Request.Body.tenantFilter
    $UPN = $Request.Body.user.value
    $Add = $Request.Body.Add -eq $true

    # Role comes from the removal picker's selected entry when present, else from the form.
    $Role = $Request.Body.user.addedFields.Group ?? $Request.Body.Role ?? 'Members'
    $MemberType = $Request.Body.user.addedFields.Type
    $AssociatedGroups = @{
        'Owners'   = 'associatedownergroup'
        'Members'  = 'associatedmembergroup'
        'Visitors' = 'associatedvisitorgroup'
    }

    try {
        if (-not $UPN) { throw 'No user was selected.' }
        if (-not $AssociatedGroups.ContainsKey([string]$Role)) {
            throw "Invalid role '$Role'. Valid roles are: $($AssociatedGroups.Keys -join ', ')."
        }

        $IsGroupSite = $Request.Body.SharePointType -eq 'Group'
        # Owners/Members of a group-connected site live in the M365 group. Visitors are always
        # a SharePoint role group. A removal of a directly-added user (Type 'User') on a group
        # site targets the SharePoint role group instead of the M365 group.
        $UseGraphGroup = $IsGroupSite -and $Role -ne 'Visitors' -and ($Add -or $MemberType -ne 'User')

        if ($UseGraphGroup) {
            if ($Request.Body.GroupID -match '^[0-9a-fA-F]{8}(-[0-9a-fA-F]{4}){3}-[0-9a-fA-F]{12}$') {
                $GroupId = $Request.Body.GroupID
            } else {
                $GroupId = (New-GraphGetRequest -uri "https://graph.microsoft.com/beta/groups?`$filter=mail eq '$($Request.Body.GroupID)' or proxyAddresses/any(x:endsWith(x,'$($Request.Body.GroupID)')) or mailNickname eq '$($Request.Body.GroupID)'" -ComplexFilter -tenantid $TenantFilter).id
            }

            if ($Role -eq 'Owners') {
                $UserID = (New-GraphGetRequest -uri "https://graph.microsoft.com/v1.0/users/$UPN`?`$select=id" -tenantid $TenantFilter).id
                if ($Add) {
                    $OwnerBody = ConvertTo-Json -Compress -InputObject @{ '@odata.id' = "https://graph.microsoft.com/v1.0/directoryObjects/$UserID" }
                    $null = New-GraphPostRequest -uri "https://graph.microsoft.com/v1.0/groups/$GroupId/owners/`$ref" -tenantid $TenantFilter -type POST -body $OwnerBody
                    $Results = "Successfully added $UPN as an owner of the M365 group backing the site."
                } else {
                    $null = New-GraphPostRequest -uri "https://graph.microsoft.com/v1.0/groups/$GroupId/owners/$UserID/`$ref" -tenantid $TenantFilter -type DELETE -body ''
                    $Results = "Successfully removed $UPN as an owner of the M365 group backing the site."
                }
                Write-LogMessage -Headers $Headers -API $APIName -tenant $TenantFilter -message $Results -sev Info
            } else {
                if ($Add) {
                    $Results = Add-CIPPGroupMember -GroupType 'Team' -GroupID $GroupID -Member $UPN -TenantFilter $TenantFilter -Headers $Headers
                } else {
                    $UserID = (New-GraphGetRequest -uri "https://graph.microsoft.com/v1.0/users/$UPN`?`$select=id" -tenantid $TenantFilter).id
                    $Results = Remove-CIPPGroupMember -GroupType 'Team' -GroupID $GroupID -Member $UserID -TenantFilter $TenantFilter -Headers $Headers
                }
            }
            $StatusCode = [HttpStatusCode]::OK
        } else {
            # SharePoint role group management via REST with certificate auth.
            $SiteUrl = $Request.Body.URL
            if (-not $SiteUrl) { throw 'No site URL was provided for this site.' }

            $SharePointInfo = Get-SharePointAdminLink -Public $false -tenantFilter $TenantFilter
            $Scope = "$($SharePointInfo.SharePointUrl)/.default"
            $JsonAccept = @{ Accept = 'application/json;odata=nometadata' }
            $BaseUri = "$($SiteUrl.TrimEnd('/'))/_api"
            $RoleGroup = $AssociatedGroups[[string]$Role]
            $RoleLabel = ([string]$Role).ToLower().TrimEnd('s')
            $Article = if ($RoleLabel -match '^[aeiou]') { 'an' } else { 'a' }

            try {
                $EnsureBody = ConvertTo-Json -Compress -InputObject @{ logonName = "i:0#.f|membership|$UPN" }
                $EnsuredUser = New-GraphPostRequest -uri "$BaseUri/web/ensureuser" -tenantid $TenantFilter -scope $Scope -type POST -body $EnsureBody -contentType 'application/json;odata=nometadata' -AddedHeaders $JsonAccept -UseCertificate -AsApp $true
            } catch {
                throw "Could not resolve $UPN on the site (ensureuser): $($_.Exception.Message)"
            }
            if (-not $EnsuredUser.Id) {
                throw "Could not resolve $UPN on the site."
            }

            if ($Add) {
                # Same shape PnP sends: an SP.User entity posted to the group's users
                # collection, which requires the odata=verbose content type.
                $AddBody = ConvertTo-Json -Compress -Depth 5 -InputObject @{
                    '__metadata' = @{ 'type' = 'SP.User' }
                    'LoginName'  = $EnsuredUser.LoginName
                }
                try {
                    $null = New-GraphPostRequest -uri "$BaseUri/web/$RoleGroup/users" -tenantid $TenantFilter -scope $Scope -type POST -body $AddBody -contentType 'application/json;odata=verbose' -AddedHeaders $JsonAccept -UseCertificate -AsApp $true
                } catch {
                    throw "Could not add $UPN to the site $Role group: $($_.Exception.Message)"
                }
                $Results = "Successfully added $UPN as $Article $RoleLabel of $SiteUrl."
            } else {
                try {
                    $null = New-GraphPostRequest -uri "$BaseUri/web/$RoleGroup/users/removebyid($($EnsuredUser.Id))" -tenantid $TenantFilter -scope $Scope -type POST -body '{}' -contentType 'application/json;odata=nometadata' -AddedHeaders $JsonAccept -UseCertificate -AsApp $true
                } catch {
                    if ($_.Exception.Message -match 'Can not find the user') {
                        throw "$UPN is not in the site's $Role group."
                    }
                    throw "Could not remove $UPN from the site $Role group: $($_.Exception.Message)"
                }
                $Results = "Successfully removed $UPN as $Article $RoleLabel of $SiteUrl."
            }
            Write-LogMessage -Headers $Headers -API $APIName -tenant $TenantFilter -message $Results -sev Info
            $StatusCode = [HttpStatusCode]::OK
        }
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        $Results = "Failed to modify $Role for $($Request.Body.URL ?? $Request.Body.GroupID). Error: $($ErrorMessage.NormalizedError)"
        Write-LogMessage -Headers $Headers -API $APIName -tenant $TenantFilter -message $Results -sev Error -LogData $ErrorMessage
        $StatusCode = [HttpStatusCode]::BadRequest
    }


    return ([HttpResponseContext]@{
            StatusCode = $StatusCode
            Body       = @{ 'Results' = $Results }
        })

}
