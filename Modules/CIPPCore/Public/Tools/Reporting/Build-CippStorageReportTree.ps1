function Build-CippStorageReportTree {
    <#
    .SYNOPSIS
        Compose the SharePoint & OneDrive Storage report as a component tree.
    .DESCRIPTION
        Pure composition from already-gathered storage data. Returns @{ Blocks; Variables }: the
        component nodes for ConvertTo-CippReportPdf and the cover/footer report variables.
    .PARAMETER Data
        TenantName, sites[] (SharePoint usage rows), oneDrive[] (OneDrive usage rows) and scan[]
        (StorageCleanupScan cache rows, rowType Site or Library; empty when no cleanup scan has run).
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)][hashtable]$Data)

    $Sites = @($Data.sites ?? @())
    $OneDrive = @($Data.oneDrive ?? @())
    $Scan = @($Data.scan ?? @())
    $Libraries = @($Scan.Where({ $_.rowType -eq 'Library' }))
    $ScanSites = @($Scan.Where({ $_.rowType -eq 'Site' }))
    $Tenant = [System.Net.WebUtility]::HtmlEncode([string]$Data.TenantName)

    $Size = {
        param($Bytes)
        if ($null -eq $Bytes -or "$Bytes" -eq '') { return '-' }
        $B = [double]$Bytes
        if ($B -gt 0 -and $B -lt 1KB) { return '< 1 KB' }
        if ($B -ge 1TB) { '{0:N2} TB' -f ($B / 1TB) } elseif ($B -ge 1GB) { '{0:N2} GB' -f ($B / 1GB) } elseif ($B -ge 1MB) { '{0:N1} MB' -f ($B / 1MB) } else { '{0:N0} KB' -f ($B / 1KB) }
    }
    $Total = { param($Rows, $Field) [double](($Rows | Measure-Object -Property $Field -Sum).Sum) }
    $Pct = { param($Part, $Whole) $P = if ($Whole -gt 0) { [math]::Round($Part / $Whole * 100, 1) } else { 0 }; if ($P -eq 0 -and $Part -gt 0) { '< 0.1%' } else { "$P%" } }
    $Activity = { param($Row) $Date = $Row.lastActivityDate -as [datetime]; if ($Date) { $Date.ToString('yyyy-MM-dd') } else { 'None recorded' } }
    $SiteNames = @{}
    foreach ($S in $Sites) { if ($S.webUrl) { $SiteNames[([string]$S.webUrl).TrimEnd('/')] = $S.displayName } }
    $SiteName = { param($Url) $Key = ([string]$Url).TrimEnd('/'); if ($SiteNames[$Key]) { $SiteNames[$Key] } else { $Key } }

    # Same split as the Storage Report page: group and channel sites are Teams storage.
    $TeamsSites = @($Sites.Where({ (([string]$_.rootWebTemplate -split '#')[0] -replace '\s', '') -in 'group', 'teamchannel' }))
    $TeamsBytes = & $Total $TeamsSites 'storageUsedInBytes'
    $SpBytes = (& $Total $Sites 'storageUsedInBytes') - $TeamsBytes
    $OdBytes = & $Total $OneDrive 'storageUsedInBytes'
    $AllBytes = $SpBytes + $TeamsBytes + $OdBytes
    $LibBytes = & $Total $Libraries 'storageUsedInBytes'
    $VersionBytes = & $Total $Libraries 'versionEstimateBytes'
    $RecycleBytes = & $Total $ScanSites 'recycleTotalBytes'
    $VersionPct = & $Pct $VersionBytes $LibBytes
    $Scanned = $Libraries.Count -gt 0
    $Warn = '#744210'

    $Cutoff = (Get-Date).AddDays(-90)
    $Inactive = @($Sites.Where({ [double]($_.storageUsedInBytes ?? 0) -gt 0 -and (-not $_.lastActivityDate -or ($_.lastActivityDate -as [datetime]) -lt $Cutoff) }))
    # Count limit with no expiry: versions pile up to the limit on every file and are never trimmed by age.
    $Unbounded = @($Libraries.Where({ $_.versionTrimMode -eq 0 -and $_.versionPolicy -ne 'Versioning off' -and [double]($_.fileCount ?? 0) -gt 0 }))
    $LibRow = { param($L) @{ site = (& $SiteName $L.siteUrl); library = $L.libraryDisplayName; total = (& $Size $L.storageUsedInBytes); versions = (& $Size $L.versionEstimateBytes); share = (& $Pct ([double]($L.versionEstimateBytes ?? 0)) ([double]($L.storageUsedInBytes ?? 0))); policy = $L.versionPolicy } }
    $LibColumns = @(@{ header = 'Site'; key = 'site'; width = 1.8 }, @{ header = 'Library'; key = 'library'; width = 1.5 }, @{ header = 'Size'; key = 'total'; width = 0.9 }, @{ header = 'Versions'; key = 'versions'; width = 0.9 }, @{ header = 'Share'; key = 'share'; width = 0.7 }, @{ header = 'Version policy'; key = 'policy'; width = 1.8 })

    $Blocks = [System.Collections.Generic.List[object]]::new()

    # -- Executive Summary --
    $Blocks.Add((New-CippReportPage -Title 'Executive Summary' -Subtitle 'How much storage is in use, and where it goes'))
    $Blocks.Add((New-CippReportParagraph -Html ("<p>SharePoint and OneDrive storage grows with every file and every saved version of it. This report shows where storage in <b>$Tenant</b> is used today, how much of it is old file versions, and which sites and libraries are worth reviewing.</p>")))
    $Blocks.Add((New-CippReportStatRow -Stats @(
                @{ value = (& $Size $SpBytes); label = 'SharePoint' }
                @{ value = (& $Size $TeamsBytes); label = 'Teams' }
                @{ value = (& $Size $OdBytes); label = 'OneDrive' }
                if ($Scanned) { @{ value = (& $Size $VersionBytes); label = 'Version History (est.)' } }
                if ($ScanSites.Count -gt 0) { @{ value = (& $Size $RecycleBytes); label = 'Recycle Bins' } }
            )))
    if ($Scanned) {
        $Blocks.Add((New-CippReportInfoBox -Title 'Version history' -Content ("Old file versions take up an estimated {0} of the {1} held in the {2} document libraries reviewed ({3}). {4}" -f (& $Size $VersionBytes), (& $Size $LibBytes), $Libraries.Count, $VersionPct, $(if ($Unbounded.Count -eq 1) { '1 of those libraries keeps versions with no time limit.' } elseif ($Unbounded.Count -gt 1) { "$($Unbounded.Count) of those libraries keep versions with no time limit." } else { 'Every library with version history trims it automatically or by age.' }))))
    }

    # -- Where storage goes --
    $Blocks.Add((New-CippReportPage -Title 'Where Storage Goes' -Subtitle 'The largest sites and OneDrive accounts'))
    $Blocks.Add((New-CippReportTable -Title 'Largest SharePoint sites' -Limit 15 -EmptyText 'No SharePoint storage data is available.' -Columns @(@{ header = 'Site'; key = 'site'; width = 2.6 }, @{ header = 'Used'; key = 'used'; width = 1 }, @{ header = 'Of all storage'; key = 'share'; width = 1 }, @{ header = 'Last activity'; key = 'activity'; width = 1.1 }) -Rows @(
                $Sites | Sort-Object { [double]($_.storageUsedInBytes ?? 0) } -Descending | Select-Object -First 15 | ForEach-Object {
                    @{ site = $_.displayName; used = (& $Size $_.storageUsedInBytes); share = (& $Pct ([double]($_.storageUsedInBytes ?? 0)) $AllBytes); activity = (& $Activity $_) }
                })))
    $Blocks.Add((New-CippReportTable -Title 'Largest OneDrive accounts' -Limit 10 -EmptyText 'No OneDrive storage data is available.' -Columns @(@{ header = 'Owner'; key = 'owner'; width = 2.6 }, @{ header = 'Used'; key = 'used'; width = 1 }, @{ header = 'Last activity'; key = 'activity'; width = 1.1 }) -Rows @(
                $OneDrive | Sort-Object { [double]($_.storageUsedInBytes ?? 0) } -Descending | Select-Object -First 10 | ForEach-Object {
                    @{ owner = $(if ($_.ownerPrincipalName) { $_.ownerPrincipalName } else { $_.displayName }); used = (& $Size $_.storageUsedInBytes); activity = (& $Activity $_) }
                })))

    # -- Version history --
    if ($Scanned) {
        $Blocks.Add((New-CippReportPage -Title 'Version History' -Subtitle 'How much storage old file versions use, and the policy behind it'))
        $Blocks.Add((New-CippReportTable -Title 'Libraries with the most version history' -Limit 15 -EmptyText 'No library holds a measurable amount of version history.' -Columns $LibColumns -Rows @(
                    $Libraries.Where({ [double]($_.versionEstimateBytes ?? 0) -gt 0 }) | Sort-Object { [double]($_.versionEstimateBytes ?? 0) } -Descending | Select-Object -First 15 | ForEach-Object { & $LibRow $_ })))
        $Blocks.Add((New-CippReportHeading -Title 'Libraries Keeping Versions With No Time Limit'))
        $Blocks.Add((New-CippReportInfoBox -Title 'Why this matters' -Content 'A count limit with no expiry keeps up to that many versions of every file indefinitely. At the default of 500, a frequently edited file can hold hundreds of old copies. Automatic version trimming keeps recent versions and thins out old ones without losing recent history.'))
        if ($Unbounded.Count -gt 0) {
            $Blocks.Add((New-CippReportAlertBox -Title ("{0} with no time limit, holding an estimated {1}" -f $(if ($Unbounded.Count -eq 1) { '1 library' } else { "$($Unbounded.Count) libraries" }), (& $Size (& $Total $Unbounded 'versionEstimateBytes'))) -Colour $Warn -Content 'Consider automatic version trimming for these libraries, or a count limit combined with an age limit.'))
            $Blocks.Add((New-CippReportTable -Limit 15 -Columns $LibColumns -Rows @(
                        $Unbounded | Sort-Object { [double]($_.versionEstimateBytes ?? 0) } -Descending | Select-Object -First 15 | ForEach-Object { & $LibRow $_ })))
        } else {
            $Blocks.Add((New-CippReportClearBox -Title 'Version history is trimmed everywhere' -Content 'Every library holding version history trims it automatically or by age.'))
        }
    }

    # -- Cleanup opportunities --
    $Blocks.Add((New-CippReportPage -Title 'Other Cleanup Opportunities' -Subtitle 'Recycle bins and inactive sites'))
    $RecycleRows = @($ScanSites.Where({ [double]($_.recycleTotalBytes ?? 0) -gt 0 }) | Sort-Object { [double]$_.recycleTotalBytes } -Descending | Select-Object -First 10 | ForEach-Object {
            @{ site = $(if ($_.displayName) { $_.displayName } else { & $SiteName $_.siteUrl }); size = (& $Size $_.recycleTotalBytes); items = "$($_.recycleItemCount)" }
        })
    if ($ScanSites.Count -gt 0) {
        $Blocks.Add((New-CippReportParagraph -Text 'Deleted files stay in the site recycle bins for 93 days and count towards storage until they are removed.'))
        $Blocks.Add((New-CippReportTable -Title 'Largest recycle bins' -Limit 10 -EmptyText 'No recycle bin holds any data.' -Columns @(@{ header = 'Site'; key = 'site'; width = 2.6 }, @{ header = 'Size'; key = 'size'; width = 1 }, @{ header = 'Items'; key = 'items'; width = 0.8 }) -Rows $RecycleRows))
    }
    if ($Inactive.Count -gt 0) {
        $Blocks.Add((New-CippReportParagraph -Text ('{0} holding {1} had no activity in the last 90 days.' -f $(if ($Inactive.Count -eq 1) { '1 site' } else { "$($Inactive.Count) sites" }), (& $Size (& $Total $Inactive 'storageUsedInBytes')))))
    }
    $Blocks.Add((New-CippReportTable -Title 'Sites with no activity in 90 days' -Limit 10 -EmptyText 'Every site with stored data has been active in the last 90 days.' -Columns @(@{ header = 'Site'; key = 'site'; width = 2.6 }, @{ header = 'Used'; key = 'used'; width = 1 }, @{ header = 'Last activity'; key = 'activity'; width = 1.1 }) -Rows @(
                $Inactive | Sort-Object { [double]($_.storageUsedInBytes ?? 0) } -Descending | Select-Object -First 10 | ForEach-Object { @{ site = $_.displayName; used = (& $Size $_.storageUsedInBytes); activity = (& $Activity $_) } })))

    # -- Recommendations --
    $Blocks.Add((New-CippReportPage -Title 'Recommendations' -Subtitle 'What to do about the findings'))
    $Blocks.Add((New-CippReportBullets -Items @(
                @{ marker = '1.'; label = 'Turn on automatic version trimming.'; text = 'Set it as the tenant default and apply it to existing libraries. It keeps recent versions and removes old ones as they age, which stops version history growing without limit.' }
                @{ marker = '2.'; label = 'Clean up existing version history.'; text = 'A version cleanup job on the largest libraries frees space now. Changing the policy alone only affects versions created from then on.' }
                @{ marker = '3.'; label = 'Review inactive sites.'; text = 'Archive or delete sites nobody uses. Microsoft 365 Archive moves them to cheaper storage while keeping them recoverable.' }
                @{ marker = '4.'; label = 'Empty large recycle bins.'; text = 'Where deleted content is not needed, emptying the second-stage recycle bin frees the space straight away.' }
                @{ marker = '5.'; label = 'Re-run this report regularly.'; text = 'Storage grows steadily. Comparing reports over time shows whether the policies are working.' }
            )))

    @{
        Blocks    = @($Blocks)
        Variables = @{
            coverlabel         = 'Storage Review'
            coversubtitle      = "Where SharePoint and OneDrive storage is used at $($Data.TenantName), how much of it is old file versions, and what can be reclaimed."
            covermeta          = ("{0} SharePoint $([char]0x00B7) {1} Teams $([char]0x00B7) {2} OneDrive" -f (& $Size $SpBytes), (& $Size $TeamsBytes), (& $Size $OdBytes))
            covermetanote      = $(if ($Scanned) { "Version history: ~$(& $Size $VersionBytes) ($VersionPct of library storage)" } else { "$($OneDrive.Count) OneDrive accounts" })
            coverfooternote    = "Confidential $([char]0x2014) For Internal Use Only"
            coverfallbackimage = '/reportImages/laptop.jpg'
            footerlabel        = "$($Data.TenantName) $([char]0x2014) SharePoint & OneDrive Storage"
        }
    }
}
