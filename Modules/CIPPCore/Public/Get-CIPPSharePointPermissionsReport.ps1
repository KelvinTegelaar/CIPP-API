function Get-CIPPSharePointPermissionsReport {
    <#
    .FUNCTIONALITY
        Internal
    .SYNOPSIS
        The SharePoint permissions report for a tenant, compiled from the CIPP reporting cache.
    .DESCRIPTION
        Rolls up the cached SharePointPermissions dataset into the shape the Permissions page
        (ListSharePointPermissions) and the permissions PDF consume: the scan summary, the oversharing
        signals worth acting on, chart datasets and the individual permission assignments. No live
        enumeration is performed; refresh the data by syncing that cache (ExecCIPPDBCache).

        Signals reported:
        - Broad claims: grants to Everyone, Everyone except external users, or All Users. A library
          carrying one of these is reachable by the whole tenant regardless of who was meant to
          have it, which is the classic oversharing footgun.
        - External grants: permissions held by guest or external identities.
        - Direct Full Control: Full Control held by something other than a SharePoint group, i.e.
          granted to a user or directory group rather than through the site's Owners group.
        - Unique permission libraries: libraries that no longer inherit from their site, so site
          level permission changes no longer reach them.

        Limited Access assignments (isSystemManaged) are excluded from every signal - SharePoint
        creates them itself so a user can traverse to an item, and they grant nothing on their own.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$TenantFilter
    )

    # A readable label for a site that has no display name, taken from the last path segment of
    # its URL: '.../sites/AllCompany' becomes 'AllCompany', '.../search' becomes 'search'.
    function Get-CIPPSiteLabel {
        param([string]$SiteUrl)
        if ([string]::IsNullOrWhiteSpace($SiteUrl)) { return 'Unnamed site' }
        try {
            $Path = ([System.Uri]$SiteUrl).AbsolutePath.Trim('/')
            if ($Path) { return ($Path -split '/')[-1] }
            return 'Root site'
        } catch {
            return 'Unnamed site'
        }
    }
    # Counts per key, largest first, as { <KeyName>; <ValueName> } rows for the charts and tables.
    function Get-RankedCount($Rows, [scriptblock]$Key, [string]$KeyName, [string]$ValueName) {
        @($Rows | Group-Object $Key | Where-Object { $_.Name } | Sort-Object -Property Count -Descending |
                ForEach-Object { [PSCustomObject]@{ $KeyName = $_.Name; $ValueName = $_.Count } })
    }

    # --- Cached dataset from the CIPP reporting database ---
    $CacheRows = try { @(New-CIPPDbRequest -TenantFilter $TenantFilter -Type 'SharePointPermissions') } catch { @() }
    $CountRow = try { Get-CIPPDbItem -TenantFilter $TenantFilter -Type 'SharePointPermissions' -CountsOnly | Select-Object -First 1 } catch { $null }

    $SiteRows = @($CacheRows | Where-Object { $_.rowType -eq 'Site' })
    $Assignments = @($CacheRows | Where-Object { $_.rowType -eq 'Assignment' })
    $SkippedSites = @($SiteRows | Where-Object { $_.collectionStatus -eq 'Skipped' } | ForEach-Object {
            [PSCustomObject]@{ siteName = $_.siteName; siteUrl = $_.siteUrl; error = $_.collectionError }
        })
    # Placeholder rows for a unique-permission library with nothing granted carry no principal, and
    # SharePoint maintains Limited Access itself; neither grants anything on its own.
    $RealAssignments = @($Assignments | Where-Object { $_.principalId -and $_.isSystemManaged -ne $true })
    $Level = { [string]($_.permissionLevel ?? 'Unknown') }

    $Body = [PSCustomObject]@{
        summary                   = [PSCustomObject]@{
            sitesScanned              = $SiteRows.Count
            sitesSkipped              = $SkippedSites.Count
            librariesScanned          = [int](($SiteRows | ForEach-Object { [int]($_.librariesScanned ?? 0) } | Measure-Object -Sum).Sum)
            uniquePermissionLibraries = [int](($SiteRows | ForEach-Object { [int]($_.librariesWithUniquePermissions ?? 0) } | Measure-Object -Sum).Sum)
            totalAssignments          = $RealAssignments.Count
            broadClaimGrants          = @($RealAssignments | Where-Object { $_.broadClaim }).Count
            externalGrants            = @($RealAssignments | Where-Object { $_.isGuest -eq $true }).Count
            # Full Control held by anything other than a SharePoint group was granted directly rather
            # than through the site's Owners group, which every site has by default.
            directFullControlGrants   = @($RealAssignments | Where-Object { (& $Level) -eq 'Full Control' -and $_.principalType -ne 'SharePoint Group' }).Count
            permissionsSynced         = [bool]$CountRow
            lastDataRefresh           = $CountRow.Timestamp
        }
        byPermissionLevel         = @(Get-RankedCount $RealAssignments $Level 'level' 'grants')
        byPrincipalType           = @(Get-RankedCount $RealAssignments { [string]($_.principalType ?? 'Other') } 'type' 'grants')
        byBroadClaim              = @(Get-RankedCount @($RealAssignments | Where-Object { $_.broadClaim }) { [string]$_.broadClaim } 'claim' 'grants')
        # Libraries that no longer inherit, counted per site for the chart.
        topSitesByUniqueLibraries = @($SiteRows | Where-Object { [int]($_.librariesWithUniquePermissions ?? 0) -gt 0 } |
                Group-Object { [string]($_.siteName ?? $_.siteUrl) } | Where-Object { $_.Name } |
                ForEach-Object { [PSCustomObject]@{ site = $_.Name; libraries = [int](($_.Group | ForEach-Object { [int]$_.librariesWithUniquePermissions } | Measure-Object -Sum).Sum) } } |
                Sort-Object -Property libraries -Descending | Select-Object -First 10)
        skippedSites              = @($SkippedSites)
        # Display fields are derived here rather than stored, so existing cached data gains them
        # without waiting for a re-scan.
        #
        # appliesTo spells out what scope means for a reader scanning the table. Every Library row
        # is by definition a library that stopped inheriting - libraries that still inherit are not
        # collected, because their permissions are the site's repeated.
        #
        # siteName falls back to a label built from the URL for the handful of system sites that
        # have no name. The URL itself is not used: the tables render any value starting with http
        # as a link, and a column of links where names should be is worse than a plain label.
        assignments               = @($Assignments | ForEach-Object {
                $AppliesTo = if ($_.scope -eq 'Library') { 'This library only' } else { 'Whole site' }
                $_ | Add-Member -NotePropertyName 'appliesTo' -NotePropertyValue $AppliesTo -Force

                $SiteName = [string]$_.siteName
                if ([string]::IsNullOrWhiteSpace($SiteName) -or $SiteName -like 'http*') {
                    $_ | Add-Member -NotePropertyName 'siteName' -NotePropertyValue (Get-CIPPSiteLabel -SiteUrl $_.siteUrl) -Force
                }
                $_
            })
    }
    return $Body
}
