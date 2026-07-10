function Push-DBCacheSharePointSiteSharingLinks {
    <#
    .SYNOPSIS
        Scans a single SharePoint/OneDrive site for sharing links and returns the rows.

    .DESCRIPTION
        Processes one site (fanned out by Set-CIPPDBCacheSharePointSharingLinks). Enumerates the
        site's drives, delta-scans each drive for items carrying the "shared" facet, fetches the
        direct (non-inherited) sharing permissions of those items and returns one row per sharing
        link (any scope) or direct grant to an external user. Delta pages are streamed and shared
        items are processed in bounded buffers so a single very large library cannot exhaust the
        worker's memory. The rows are returned to the orchestrator; Push-StoreSharePointSharingLinks
        aggregates every site and writes the cache once.

    .FUNCTIONALITY
        Entrypoint
    #>
    [CmdletBinding()]
    param($Item)

    $TenantFilter = $Item.TenantFilter
    $SiteId = $Item.SiteId
    $SiteName = $Item.SiteName
    $SiteUrl = $Item.SiteUrl
    $IsPersonalSite = [bool]$Item.IsPersonalSite

    # Verified domains passed from the parent; used to tell internal from external recipients.
    $InternalDomains = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    foreach ($Domain in @($Item.InternalDomains)) { if ($Domain) { [void]$InternalDomains.Add([string]$Domain) } }

    # Returns $true when an identity (link recipient or direct grant) is external to the tenant.
    function Test-CIPPExternalIdentity {
        param($Identity, $InternalDomains)
        $LoginName = [string]($Identity.siteUser.loginName ?? $Identity.user.loginName ?? '')
        if ($LoginName -match '#ext#' -or $LoginName -match 'urn%3aspo%3aguest' -or $LoginName -match 'urn:spo:guest') { return $true }
        $Email = [string]($Identity.user.email ?? $Identity.user.userPrincipalName ?? $Identity.siteUser.email ?? '')
        if ($Email -match '#EXT#') { return $true }
        if ($Email -and $Email.Contains('@') -and $InternalDomains.Count -gt 0) {
            return -not $InternalDomains.Contains($Email.Split('@')[-1])
        }
        return $false
    }

    # Friendly display value for an identity, preferring email over display name.
    function Get-CIPPIdentityLabel {
        param($Identity)
        $Identity.user.email ?? $Identity.user.userPrincipalName ?? $Identity.siteUser.email ?? $Identity.user.displayName ?? $Identity.siteUser.displayName ?? $Identity.group.email ?? $Identity.group.displayName ?? $Identity.siteGroup.displayName
    }

    $Rows = [System.Collections.Generic.List[object]]::new()

    # Fetch permissions for a buffer of shared items and append their sharing-link rows.
    function Add-CIPPSharingRows {
        param($Buffer, $Drive, $Site, $InternalDomains, $TenantFilter, $RowsOut)

        if (@($Buffer).Count -eq 0) { return }

        $ItemByRequestId = @{}
        $RequestId = 0
        $PermissionRequests = foreach ($SharedItem in $Buffer) {
            $ItemByRequestId["$RequestId"] = $SharedItem
            @{
                id     = "$RequestId"
                method = 'GET'
                url    = "drives/$($Drive.id)/items/$($SharedItem.id)/permissions"
            }
            $RequestId++
        }

        $PermissionResponses = New-GraphBulkRequest -tenantid $TenantFilter -Requests @($PermissionRequests) -asapp $true
        foreach ($Response in $PermissionResponses) {
            if ($Response.status -and $Response.status -ne 200) { continue }
            $DriveItem = $ItemByRequestId["$($Response.id)"]

            foreach ($Permission in @($Response.body.value)) {
                # Only permissions set on the item itself; inherited ones are reported on their parent.
                if ($Permission.inheritedFrom) { continue }

                if ($Permission.link) {
                    $Recipients = @($Permission.grantedToIdentitiesV2 ?? $Permission.grantedToIdentities)
                    $LinkScope = $Permission.link.scope ?? 'users'
                    $Classification = switch ($LinkScope) {
                        'anonymous' { 'Anonymous' }
                        'organization' { 'Internal' }
                        'existingAccess' { 'Internal' }
                        default {
                            $HasExternal = $false
                            foreach ($Recipient in $Recipients) {
                                if (Test-CIPPExternalIdentity -Identity $Recipient -InternalDomains $InternalDomains) { $HasExternal = $true; break }
                            }
                            if ($HasExternal) { 'External' } else { 'Internal' }
                        }
                    }
                    $LinkType = $Permission.link.type ?? 'link'
                    $LinkUrl = $Permission.link.webUrl
                } else {
                    # Direct grant (no sharing link): only report grants to external users.
                    $Recipients = @($Permission.grantedToV2 ?? $Permission.grantedTo)
                    if ($Permission.roles -contains 'owner') { continue }
                    $HasExternal = $false
                    foreach ($Recipient in $Recipients) {
                        if (Test-CIPPExternalIdentity -Identity $Recipient -InternalDomains $InternalDomains) { $HasExternal = $true; break }
                    }
                    if (-not $HasExternal) { continue }
                    $Classification = 'External'
                    $LinkScope = 'direct'
                    $LinkType = 'directGrant'
                    $LinkUrl = $null
                }

                $SharedWith = @($Recipients | ForEach-Object { Get-CIPPIdentityLabel -Identity $_ } | Where-Object { $_ } | Sort-Object -Unique)

                $RowsOut.Add([PSCustomObject]@{
                        id                   = "$($Drive.id)_$($DriveItem.id)_$($Permission.id)"
                        siteId               = $Site.SiteId
                        siteName             = $Site.SiteName
                        siteUrl              = $Site.SiteUrl
                        workload             = if ($Site.IsPersonalSite) { 'OneDrive' } else { 'SharePoint' }
                        driveId              = $Drive.id
                        driveName            = $Drive.name
                        itemId               = $DriveItem.id
                        fileName             = $DriveItem.name
                        itemUrl              = $DriveItem.webUrl
                        itemType             = if ($DriveItem.folder) { 'Folder' } else { 'File' }
                        size                 = $DriveItem.size
                        lastModifiedDateTime = $DriveItem.lastModifiedDateTime
                        permissionId         = $Permission.id
                        linkType             = $LinkType
                        linkScope            = $LinkScope
                        classification       = $Classification
                        roles                = @($Permission.roles)
                        sharedWith           = $SharedWith
                        linkUrl              = $LinkUrl
                        hasPassword          = $Permission.hasPassword ?? $false
                        expirationDateTime   = $Permission.expirationDateTime
                    })
            }
        }
    }

    try {
        # 1) Drives (document libraries) for this one site.
        $Drives = @()
        try {
            $Drives = @(New-GraphGetRequest -uri "https://graph.microsoft.com/beta/sites/$SiteId/drives?`$select=id,name,driveType,webUrl" -tenantid $TenantFilter -asapp $true)
        } catch {
            Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message "Sharing links: could not list drives for '$SiteUrl': $($_.Exception.Message)" -sev Warning
            return @()
        }

        $SiteContext = [PSCustomObject]@{
            SiteId         = $SiteId
            SiteName       = $SiteName
            SiteUrl        = $SiteUrl
            IsPersonalSite = $IsPersonalSite
        }
        $PermissionBufferSize = 200

        # 2) Delta-scan each drive, streaming pages so a huge library never loads at once.
        #    Shared items are buffered and flushed to permission lookups in bounded chunks.
        foreach ($Drive in $Drives) {
            if (-not $Drive.id) { continue }
            $Buffer = [System.Collections.Generic.List[object]]::new()
            try {
                New-GraphGetRequest -uri "https://graph.microsoft.com/beta/drives/$($Drive.id)/root/delta?`$select=id,name,webUrl,folder,shared,size,lastModifiedDateTime&`$top=999" -tenantid $TenantFilter -asapp $true -Stream |
                    Where-Object { $_.shared -and -not $_.deleted } |
                    ForEach-Object {
                        $Buffer.Add($_)
                        if ($Buffer.Count -ge $PermissionBufferSize) {
                            Add-CIPPSharingRows -Buffer $Buffer -Drive $Drive -Site $SiteContext -InternalDomains $InternalDomains -TenantFilter $TenantFilter -RowsOut $Rows
                            $Buffer.Clear()
                        }
                    }
                # Flush the remainder for this drive.
                Add-CIPPSharingRows -Buffer $Buffer -Drive $Drive -Site $SiteContext -InternalDomains $InternalDomains -TenantFilter $TenantFilter -RowsOut $Rows
            } catch {
                Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message "Sharing links: failed scanning drive '$($Drive.name)' on '$SiteUrl': $($_.Exception.Message)" -sev Warning
            } finally {
                $Buffer = $null
                [System.GC]::Collect()
            }
        }

        return @($Rows)

    } catch {
        Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message "Sharing links: failed scanning site '$SiteUrl': $($_.Exception.Message)" -sev Error -LogData (Get-CippException -Exception $_)
        return @($Rows)
    }
}
