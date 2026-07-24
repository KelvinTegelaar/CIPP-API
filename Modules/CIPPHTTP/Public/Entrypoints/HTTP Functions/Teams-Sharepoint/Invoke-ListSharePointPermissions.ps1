function Invoke-ListSharePointPermissions {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        Sharepoint.Site.Read
    .DESCRIPTION
        Compiles the SharePoint permissions report for a tenant from CACHED data in the CIPP
        reporting database (SharePointPermissions). No live enumeration is performed - refresh the
        data by syncing that cache (ExecCIPPDBCache). Returns the scan summary, the oversharing
        signals worth acting on, chart datasets and the individual permission assignments.

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
    param($Request, $TriggerMetadata)

    $TenantFilter = $Request.Query.tenantFilter ?? $Request.Body.tenantFilter

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

    # --- Cached dataset from the CIPP reporting database ---
    try {
        $CacheRows = @(New-CIPPDbRequest -TenantFilter $TenantFilter -Type 'SharePointPermissions')
    } catch {
        $CacheRows = @()
    }

    $PermissionsSynced = $false
    $LastDataRefresh = $null
    try {
        $CountRow = Get-CIPPDbItem -TenantFilter $TenantFilter -Type 'SharePointPermissions' -CountsOnly | Select-Object -First 1
        if ($CountRow) { $PermissionsSynced = $true }
        if ($CountRow.Timestamp) { $LastDataRefresh = $CountRow.Timestamp }
    } catch {}

    $SiteRows = @($CacheRows | Where-Object { $_.rowType -eq 'Site' })
    $Assignments = @($CacheRows | Where-Object { $_.rowType -eq 'Assignment' })

    # --- Scan coverage ---
    $SitesScanned = 0; $LibrariesScanned = 0; $UniquePermissionLibraries = 0
    $SkippedSites = [System.Collections.Generic.List[object]]::new()
    foreach ($Site in $SiteRows) {
        $SitesScanned++
        $LibrariesScanned += [int]($Site.librariesScanned ?? 0)
        $UniquePermissionLibraries += [int]($Site.librariesWithUniquePermissions ?? 0)
        if ($Site.collectionStatus -eq 'Skipped') {
            $SkippedSites.Add([PSCustomObject]@{
                    siteName = $Site.siteName
                    siteUrl  = $Site.siteUrl
                    error    = $Site.collectionError
                })
        }
    }

    # --- Assignment rollups ---
    $BroadClaimGrants = 0; $ExternalGrants = 0; $DirectFullControlGrants = 0
    $ByPermissionLevel = @{}
    $ByPrincipalType = @{}
    $ByBroadClaim = @{}
    $BySiteUnique = @{}
    $RealAssignments = 0
    foreach ($Assignment in $Assignments) {
        # Placeholder rows for a unique-permission library with nothing granted carry no principal.
        if (-not $Assignment.principalId) { continue }
        # SharePoint maintains Limited Access itself; it grants nothing on its own.
        if ($Assignment.isSystemManaged -eq $true) { continue }
        $RealAssignments++

        $Level = [string]($Assignment.permissionLevel ?? 'Unknown')
        $ByPermissionLevel[$Level] = [int]($ByPermissionLevel[$Level] ?? 0) + 1
        $Type = [string]($Assignment.principalType ?? 'Other')
        $ByPrincipalType[$Type] = [int]($ByPrincipalType[$Type] ?? 0) + 1

        if ($Assignment.broadClaim) {
            $BroadClaimGrants++
            $Claim = [string]$Assignment.broadClaim
            $ByBroadClaim[$Claim] = [int]($ByBroadClaim[$Claim] ?? 0) + 1
        }
        if ($Assignment.isGuest -eq $true) { $ExternalGrants++ }
        # Full Control held by anything other than a SharePoint group means it was granted
        # directly rather than through the site's Owners group, which every site has by default.
        if ($Level -eq 'Full Control' -and $Assignment.principalType -ne 'SharePoint Group') {
            $DirectFullControlGrants++
        }
    }

    # Libraries that no longer inherit, counted per site for the chart.
    foreach ($Site in $SiteRows) {
        $Unique = [int]($Site.librariesWithUniquePermissions ?? 0)
        if ($Unique -gt 0) {
            $SiteName = [string]($Site.siteName ?? $Site.siteUrl)
            if ($SiteName) { $BySiteUnique[$SiteName] = [int]($BySiteUnique[$SiteName] ?? 0) + $Unique }
        }
    }

    $Body = [PSCustomObject]@{
        summary                   = [PSCustomObject]@{
            sitesScanned              = $SitesScanned
            sitesSkipped              = $SkippedSites.Count
            librariesScanned          = $LibrariesScanned
            uniquePermissionLibraries = $UniquePermissionLibraries
            totalAssignments          = $RealAssignments
            broadClaimGrants          = $BroadClaimGrants
            externalGrants            = $ExternalGrants
            directFullControlGrants   = $DirectFullControlGrants
            permissionsSynced         = $PermissionsSynced
            lastDataRefresh           = $LastDataRefresh
        }
        byPermissionLevel         = @($ByPermissionLevel.GetEnumerator() | Sort-Object -Property Value -Descending | ForEach-Object { [PSCustomObject]@{ level = $_.Key; grants = $_.Value } })
        byPrincipalType           = @($ByPrincipalType.GetEnumerator() | Sort-Object -Property Value -Descending | ForEach-Object { [PSCustomObject]@{ type = $_.Key; grants = $_.Value } })
        byBroadClaim              = @($ByBroadClaim.GetEnumerator() | Sort-Object -Property Value -Descending | ForEach-Object { [PSCustomObject]@{ claim = $_.Key; grants = $_.Value } })
        topSitesByUniqueLibraries = @($BySiteUnique.GetEnumerator() | Sort-Object -Property Value -Descending | Select-Object -First 10 | ForEach-Object { [PSCustomObject]@{ site = $_.Key; libraries = $_.Value } })
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

    return ([HttpResponseContext]@{
            StatusCode = [HttpStatusCode]::OK
            Body       = $Body
        })
}
