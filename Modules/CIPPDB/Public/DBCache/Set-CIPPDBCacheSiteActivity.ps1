function Set-CIPPDBCacheSiteActivity {
    <#
    .SYNOPSIS
        Caches per-site activity from Microsoft usage reports for a tenant.

    .DESCRIPTION
        SiteActivity is not SharePoint-, OneDrive-, or Teams-specific. It stores one row per siteId
        with a siteType classifier (SharePoint, SharePointAndTeams, OneDrive) and workload-prefixed
        activity columns. SharePoint, OneDrive, and Teams are current data sources — additional
        workloads could add their own prefixed fields later without new cache types.

        Each row also includes teamLinkResolutionStatus (Complete/Partial) so consumers can gauge
        whether Team-link enrichment was fully resolved for the run.

        Site membership is the union of non-deleted rows from getSharePointSiteUsageDetail and
        getOneDriveUsageAccountDetail, but a row is written only when required fields for its
        siteType are present after getAllSites backfill (incomplete report rows are skipped).
        sites/getAllSites is identity backfill only (displayName, webUrl, isPersonalSite, etc.).
        Stored id/siteId values are normalized (lowercase, no braces) for stable Add-CIPPDbItem row keys.

        SharePointAndTeams means a provisioned Team exists for the Group-connected site, not that
        the team activity report contains a row. teamsLastActivityDate may be null when the Team
        exists but had no activity in the D180 window.

        effectiveLastActivityDate: passthrough report values for all siteTypes; for SharePointAndTeams
        uses whichever of sharePointLastActivityDate and teamsLastActivityDate is later (original string).

        Foundational fetches (SP report, OneDrive report, getAllSites, getTeamsTeamActivityDetail) run
        as one New-GraphBulkRequest and must succeed or the cache write is aborted. Graph usage reports
        are not license-gated at the API level — unlicensed or inactive workloads typically return empty
        rows, not errors. The SharePoint license gate above only skips tenants CIPP knows lack
        SP/OneDrive SKUs before calling Graph. Team-provisioned groups lookup and bulk
        groups/{id}/sites/root resolution are non-fatal enrichments. Graph groups list cannot
        $expand=sites — site sharepointIds require per-group sites/root calls (batched).

        Cache write behavior follows CIPPDB convention: on foundational fetch failure, the function
        logs and exits without replacing existing SiteActivity rows (last-known-good is preserved).

        Report data reflects a D180 window with typical Microsoft report lag.

    .PARAMETER TenantFilter
        The tenant to cache site activity for

    .PARAMETER QueueId
        Optional queue context passed by orchestrators; reserved for queue-aware cache flows.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$TenantFilter,
        [string]$QueueId
    )

    try {
        $LicenseCheck = Test-CIPPStandardLicense -StandardName 'SiteActivityCache' -TenantFilter $TenantFilter -Preset SharePoint -SkipLog
        if ($LicenseCheck -eq $false) {
            Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message 'Tenant does not have SharePoint/OneDrive license, skipping SiteActivity cache' -sev Debug
            return
        }

        Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message 'Caching SiteActivity' -sev Debug

        $FoundationalRequests = @(
            @{
                id     = 'sharePointUsage'
                method = 'GET'
                url    = "reports/getSharePointSiteUsageDetail(period='D180')?`$format=application/json"
            }
            @{
                id     = 'oneDriveUsage'
                method = 'GET'
                url    = "reports/getOneDriveUsageAccountDetail(period='D180')?`$format=application/json"
            }
            @{
                id     = 'listAllSites'
                method = 'GET'
                url    = "sites/getAllSites?`$select=id,webUrl,displayName,isPersonalSite,createdDateTime,sharepointIds&`$top=999"
            }
            @{
                id     = 'teamsActivity'
                method = 'GET'
                url    = "reports/getTeamsTeamActivityDetail(period='D180')?`$format=application/json"
            }
        )
        $FoundationalResults = @(New-GraphBulkRequest -tenantid $TenantFilter -Requests @($FoundationalRequests) -asapp $true)

        function Get-SiteActivityBulkReportRows {
            param(
                [Parameter(Mandatory = $true)]$Responses,
                [Parameter(Mandatory = $true)][string]$Id,
                [Parameter(Mandatory = $true)][string]$Label
            )
            $Response = $Responses | Where-Object { $_.id -eq $Id } | Select-Object -First 1
            if (-not $Response) {
                throw "$Label response missing from Graph bulk batch"
            }
            if ($Response.status -and $Response.status -ne 200) {
                throw ($Response.body.error.message ?? "$Label request failed with status $($Response.status)")
            }
            $Body = $Response.body
            if ($Body -is [string]) {
                $Json = [System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String($Body))
                return @(($Json | ConvertFrom-Json).value)
            }
            return @($Body.value)
        }

        $SharePointRows = @(Get-SiteActivityBulkReportRows -Responses $FoundationalResults -Id 'sharePointUsage' -Label 'SharePoint site usage report')
        $OneDriveRows = @(Get-SiteActivityBulkReportRows -Responses $FoundationalResults -Id 'oneDriveUsage' -Label 'OneDrive usage report')
        $TeamRows = @(Get-SiteActivityBulkReportRows -Responses $FoundationalResults -Id 'teamsActivity' -Label 'Teams team activity report')

        $AllSitesResponse = $FoundationalResults | Where-Object { $_.id -eq 'listAllSites' } | Select-Object -First 1
        if (-not $AllSitesResponse) {
            throw 'getAllSites response missing from Graph bulk batch'
        }
        if ($AllSitesResponse.status -and $AllSitesResponse.status -ne 200) {
            throw ($AllSitesResponse.body.error.message ?? "getAllSites request failed with status $($AllSitesResponse.status)")
        }
        $AllSites = @($AllSitesResponse.body.value)

        $SiteIndex = @{}
        foreach ($Site in $AllSites) {
            if ($null -eq $Site -or -not $Site.sharepointIds.siteId) { continue }
            $IndexKey = $Site.sharepointIds.siteId.ToString().Trim().Trim('{}').ToLowerInvariant()
            if ($IndexKey -and -not $SiteIndex.ContainsKey($IndexKey)) {
                $SiteIndex[$IndexKey] = $Site
            }
        }

        $TeamActivityById = @{}
        foreach ($Team in $TeamRows) {
            if (-not $Team.teamId) { continue }
            $TeamKey = $Team.teamId.ToString().Trim().Trim('{}').ToLowerInvariant()
            if ($TeamKey -eq '00000000-0000-0000-0000-000000000000') { continue }
            $TeamActivityById[$TeamKey] = $Team
        }

        # Run-level Team link enrichment quality indicator written to every record.
        $TeamLinkResolutionStatus = 'Complete'
        $TeamProvisionedById = @{}
        try {
            $TeamGroups = @(New-GraphGetRequest -tenantid $TenantFilter -uri "https://graph.microsoft.com/beta/groups?`$filter=resourceProvisioningOptions/Any(x:x eq 'Team')&`$select=id,displayName&`$top=999" -AsApp $true)
            foreach ($Group in $TeamGroups) {
                if (-not $Group.id) { continue }
                $GroupKey = $Group.id.ToString().Trim().Trim('{}').ToLowerInvariant()
                if ($GroupKey -eq '00000000-0000-0000-0000-000000000000') { continue }
                $TeamProvisionedById[$GroupKey] = $Group
            }
        } catch {
            $TeamLinkResolutionStatus = 'Partial'
            $GroupError = Get-CippException -Exception $_
            Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message "SiteActivity: unable to load Team-provisioned groups (continuing): $($GroupError.NormalizedError)" -Sev 'Warning' -LogData $GroupError
        }

        # Graph groups list does not support $expand=sites; resolve Team siteId per group via bulk sites/root.
        # Any partial failure downgrades Team link resolution status for the entire run.
        $TeamSiteBySiteKey = @{}
        if ($TeamProvisionedById.Count -gt 0) {
            try {
                $TeamSiteRequests = foreach ($GroupKey in $TeamProvisionedById.Keys) {
                    @{
                        id     = $GroupKey
                        method = 'GET'
                        url    = "groups/$GroupKey/sites/root?`$select=sharepointIds,webUrl,displayName"
                    }
                }
                $TeamSiteResponses = @(New-GraphBulkRequest -tenantid $TenantFilter -Requests @($TeamSiteRequests) -AsApp $true)
                $TeamSiteFailures = 0
                foreach ($Response in $TeamSiteResponses) {
                    if ($Response.status -ne 200 -or -not $Response.body.sharepointIds.siteId) {
                        $TeamSiteFailures++
                        continue
                    }
                    $MappedSiteKey = $Response.body.sharepointIds.siteId.ToString().Trim().Trim('{}').ToLowerInvariant()
                    if (-not $MappedSiteKey) { continue }
                    $TeamSiteBySiteKey[$MappedSiteKey] = $Response.id
                }
                if ($TeamSiteFailures -gt 0) {
                    $TeamLinkResolutionStatus = 'Partial'
                    Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message "SiteActivity: $TeamSiteFailures Team site lookups failed or returned no sharepointIds (continuing)" -sev Debug
                }
            } catch {
                $TeamLinkResolutionStatus = 'Partial'
                $TeamSiteError = Get-CippException -Exception $_
                Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message "SiteActivity: unable to resolve Team SharePoint sites (continuing): $($TeamSiteError.NormalizedError)" -Sev 'Warning' -LogData $TeamSiteError
            }
        }

        $CachedAt = (Get-Date).ToString('o')
        $OneDriveSiteIds = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
        $Records = [System.Collections.Generic.List[object]]::new()
        $SkippedIncomplete = 0

        function Test-SiteActivityCacheComplete {
            param(
                [Parameter(Mandatory = $true)]
                [string]$SiteType,
                [string]$WebUrl,
                [string]$DisplayName,
                [string]$TeamsTeamId,
                [string]$TeamsTeamName,
                [string]$OwnerPrincipalName
            )
            if ([string]::IsNullOrWhiteSpace($WebUrl)) { return $false }
            if ([string]::IsNullOrWhiteSpace($DisplayName)) { return $false }
            switch ($SiteType) {
                'OneDrive' {
                    if ([string]::IsNullOrWhiteSpace($OwnerPrincipalName)) { return $false }
                }
                'SharePointAndTeams' {
                    if ([string]::IsNullOrWhiteSpace($TeamsTeamId)) { return $false }
                    if ([string]::IsNullOrWhiteSpace($TeamsTeamName)) { return $false }
                }
            }
            return $true
        }

        foreach ($Row in $OneDriveRows) {
            if ($null -eq $Row -or $Row.isDeleted -eq $true) { continue }
            if (-not $Row.siteId) { continue }

            $SiteKey = $Row.siteId.ToString().Trim().Trim('{}').ToLowerInvariant()
            if (-not $SiteKey) { continue }

            $IndexedSite = $SiteIndex[$SiteKey]
            $WebUrl = $Row.siteUrl
            if ([string]::IsNullOrWhiteSpace($WebUrl)) { $WebUrl = $IndexedSite.webUrl }

            $DisplayName = $Row.displayName
            if ([string]::IsNullOrWhiteSpace($DisplayName)) { $DisplayName = $IndexedSite.displayName }
            if ([string]::IsNullOrWhiteSpace($DisplayName)) { $DisplayName = $Row.ownerDisplayName }

            if (-not (Test-SiteActivityCacheComplete -SiteType 'OneDrive' -WebUrl $WebUrl -DisplayName $DisplayName -OwnerPrincipalName $Row.ownerPrincipalName)) {
                $SkippedIncomplete++
                continue
            }

            [void]$OneDriveSiteIds.Add($SiteKey)
            $OneDriveLastActivity = $Row.lastActivityDate

            $Records.Add([PSCustomObject]@{
                    id                           = $SiteKey
                    siteId                       = $SiteKey
                    siteType                     = 'OneDrive'
                    effectiveLastActivityDate    = $OneDriveLastActivity
                    webUrl                       = $WebUrl
                    displayName                  = $DisplayName
                    ownerDisplayName             = $Row.ownerDisplayName
                    ownerPrincipalName           = $Row.ownerPrincipalName
                    rootWebTemplate              = $Row.rootWebTemplate
                    isPersonalSite               = $true
                    isDeleted                    = $false
                    createdDateTime              = $IndexedSite?.createdDateTime
                    webId                        = $IndexedSite?.sharepointIds?.webId
                    oneDriveLastActivityDate     = $OneDriveLastActivity
                    oneDriveFileCount            = $Row.fileCount
                    oneDriveStorageUsedInBytes   = $Row.storageUsedInBytes
                    oneDriveStorageAllocatedInBytes = $Row.storageAllocatedInBytes
                    teamLinkResolutionStatus     = $TeamLinkResolutionStatus
                    reportPeriod                 = 'D180'
                    cachedAt                     = $CachedAt
                })
        }

        foreach ($Row in $SharePointRows) {
            if ($null -eq $Row -or $Row.isDeleted -eq $true) { continue }
            if (-not $Row.siteId) { continue }

            $SiteKey = $Row.siteId.ToString().Trim().Trim('{}').ToLowerInvariant()
            if (-not $SiteKey) { continue }
            if ($OneDriveSiteIds.Contains($SiteKey)) { continue }
            if ($Row.rootWebTemplate -eq 'SPSPERS') { continue }

            $IndexedSite = $SiteIndex[$SiteKey]
            if ($IndexedSite.isPersonalSite -eq $true) { continue }

            $WebUrl = $Row.siteUrl
            if ([string]::IsNullOrWhiteSpace($WebUrl)) { $WebUrl = $IndexedSite.webUrl }

            $DisplayName = $Row.displayName
            if ([string]::IsNullOrWhiteSpace($DisplayName)) { $DisplayName = $IndexedSite.displayName }
            if ([string]::IsNullOrWhiteSpace($DisplayName)) { $DisplayName = $Row.ownerDisplayName }

            $SharePointLastActivity = $Row.lastActivityDate
            $SiteType = 'SharePoint'
            $TeamsTeamId = $null
            $TeamsTeamName = $null
            $TeamsLastActivity = $null
            $TeamsLinkStatus = $null
            $EffectiveLastActivity = $SharePointLastActivity

            if ($TeamSiteBySiteKey.ContainsKey($SiteKey)) {
                $GroupId = $TeamSiteBySiteKey[$SiteKey]
                $SiteType = 'SharePointAndTeams'
                $TeamsTeamId = $GroupId
                $ProvisionedGroup = $TeamProvisionedById[$GroupId]
                $TeamsTeamName = $ProvisionedGroup.displayName
                $TeamsLinkStatus = 'Linked'

                if ($TeamActivityById.ContainsKey($GroupId)) {
                    $TeamRow = $TeamActivityById[$GroupId]
                    if ($TeamRow.teamName) { $TeamsTeamName = $TeamRow.teamName }
                    $TeamsLastActivity = $TeamRow.lastActivityDate
                }

                if ($TeamsLastActivity) {
                    if ($SharePointLastActivity) {
                        try {
                            if ([datetime]$TeamsLastActivity -gt [datetime]$SharePointLastActivity) {
                                $EffectiveLastActivity = $TeamsLastActivity
                            }
                        } catch {
                            $EffectiveLastActivity = $TeamsLastActivity
                        }
                    } else {
                        $EffectiveLastActivity = $TeamsLastActivity
                    }
                }
            }

            $Record = [PSCustomObject]@{
                id                              = $SiteKey
                siteId                          = $SiteKey
                siteType                        = $SiteType
                effectiveLastActivityDate       = $EffectiveLastActivity
                webUrl                          = $WebUrl
                displayName                     = $DisplayName
                ownerDisplayName                = $Row.ownerDisplayName
                ownerPrincipalName              = $Row.ownerPrincipalName
                rootWebTemplate                 = $Row.rootWebTemplate
                isPersonalSite                  = $false
                isDeleted                       = $false
                createdDateTime                 = $IndexedSite?.createdDateTime
                webId                           = $IndexedSite?.sharepointIds?.webId
                sharePointLastActivityDate      = $SharePointLastActivity
                sharePointFileCount             = $Row.fileCount
                sharePointStorageUsedInBytes    = $Row.storageUsedInBytes
                sharePointStorageAllocatedInBytes = $Row.storageAllocatedInBytes
                teamLinkResolutionStatus        = $TeamLinkResolutionStatus
                reportPeriod                    = 'D180'
                cachedAt                        = $CachedAt
            }

            if ($SiteType -eq 'SharePointAndTeams') {
                $Record | Add-Member -NotePropertyName 'teamsTeamId' -NotePropertyValue $TeamsTeamId -Force
                $Record | Add-Member -NotePropertyName 'teamsTeamName' -NotePropertyValue $TeamsTeamName -Force
                $Record | Add-Member -NotePropertyName 'teamsLastActivityDate' -NotePropertyValue $TeamsLastActivity -Force
                $Record | Add-Member -NotePropertyName 'teamsLinkStatus' -NotePropertyValue $TeamsLinkStatus -Force
            }

            if (-not (Test-SiteActivityCacheComplete -SiteType $SiteType -WebUrl $WebUrl -DisplayName $DisplayName -TeamsTeamId $TeamsTeamId -TeamsTeamName $TeamsTeamName)) {
                $SkippedIncomplete++
                continue
            }

            $Records.Add($Record)
        }

        if ($SkippedIncomplete -gt 0) {
            Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message "SiteActivity: skipped $SkippedIncomplete report rows with incomplete required data" -sev Debug
        }

        if ($Records.Count -eq 0) {
            if ($SkippedIncomplete -gt 0) {
                Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message "SiteActivity: no rows were cache-complete (skipped $SkippedIncomplete); preserving existing SiteActivity cache" -sev Warning
                return
            }
            Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message 'No site activity rows to cache; writing empty SiteActivity cache' -sev Debug
            Add-CIPPDbItem -TenantFilter $TenantFilter -Type 'SiteActivity' -Data @() -AddCount
            return
        }

        Add-CIPPDbItem -TenantFilter $TenantFilter -Type 'SiteActivity' -Data @($Records) -AddCount
        Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message "Cached SiteActivity successfully ($($Records.Count) sites)" -sev Debug

    } catch {
        Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message "Failed to cache SiteActivity: $($_.Exception.Message)" -sev Error -LogData (Get-CippException -Exception $_)
    }
}
