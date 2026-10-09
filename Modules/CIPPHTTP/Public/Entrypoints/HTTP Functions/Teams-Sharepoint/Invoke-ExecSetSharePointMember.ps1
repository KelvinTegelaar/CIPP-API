function Invoke-ExecSetSharePointMember {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        Sharepoint.Site.ReadWrite
    .DESCRIPTION
        Adds one or more users to, or removes a user from, a SharePoint site role (Owners, Members or Visitors).
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

    # Role comes from the removal picker's selected entry when present, else from the form.
    $MemberParams = @{
        TenantFilter      = $TenantFilter
        UserPrincipalName = @($Request.Body.user.value | Where-Object { $_ })
        Role              = @($Request.Body.user.addedFields.Group)[0] ?? $Request.Body.Role ?? 'Members'
        Add               = $Request.Body.Add -eq $true
        SharePointType    = $Request.Body.SharePointType
        GroupId           = $Request.Body.GroupID
        SiteUrl           = $Request.Body.URL
        MemberType        = @($Request.Body.user.addedFields.Type)[0]
        Headers           = $Headers
        APIName           = $APIName
    }

    if ($MemberParams.UserPrincipalName.Count -eq 0) {
        return ([HttpResponseContext]@{ StatusCode = [HttpStatusCode]::BadRequest; Body = @{ 'Results' = 'No user was selected.' } })
    }
    if ($MemberParams.Role -notin @('Owners', 'Members', 'Visitors')) {
        return ([HttpResponseContext]@{ StatusCode = [HttpStatusCode]::BadRequest; Body = @{ 'Results' = "Invalid role '$($MemberParams.Role)'. Valid roles are: Owners, Members, Visitors." } })
    }

    try {
        $Results = @(Set-CIPPSharePointSiteMember @MemberParams)
        $StatusCode = Get-CippBulkStatusCode -Total $Results.Count -Failed $Results.Where({ $_.state -eq 'error' }).Count
    } catch {
        $Results = $_.Exception.Message
        $StatusCode = Get-CippErrorStatusCode -ErrorRecord $_
    }

    return ([HttpResponseContext]@{
            StatusCode = $StatusCode
            Body       = @{ 'Results' = $Results }
        })

}
