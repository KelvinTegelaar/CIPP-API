function Get-CIPPSharePointSiteUsageReport {
    <#
    .SYNOPSIS
        Generates a SharePoint site usage report from the CIPP Reporting database

    .DESCRIPTION
        Retrieves cached SharePoint site listing and usage data and combines them to match
        the payload shape of Invoke-ListSites for Type=SharePointSiteUsage.

    .PARAMETER TenantFilter
        The tenant to generate the report for
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$TenantFilter
    )

    try {
        if ($TenantFilter -eq 'AllTenants') {
            $AllSiteItems = Get-CIPPDbItem -TenantFilter 'allTenants' -Type 'SharePointSiteListing'
            $Tenants = @($AllSiteItems | Where-Object { $_.RowKey -ne 'SharePointSiteListing-Count' } | Select-Object -ExpandProperty PartitionKey -Unique)

            $TenantList = Get-Tenants -IncludeErrors
            $Tenants = $Tenants | Where-Object { $TenantList.defaultDomainName -contains $_ }

            $AllResults = [System.Collections.Generic.List[PSCustomObject]]::new()
            foreach ($Tenant in $Tenants) {
                try {
                    $TenantResults = Get-CIPPSharePointSiteUsageReport -TenantFilter $Tenant
                    foreach ($Result in $TenantResults) {
                        $Result | Add-Member -NotePropertyName 'Tenant' -NotePropertyValue $Tenant -Force
                        $AllResults.Add($Result)
                    }
                } catch {
                    Write-LogMessage -API 'SharePointSiteUsageReport' -tenant $Tenant -message "Failed to get report for tenant: $($_.Exception.Message)" -sev Warning
                }
            }
            return $AllResults
        }

        $SiteItems = @(Get-CIPPDbItem -TenantFilter $TenantFilter -Type 'SharePointSiteListing' | Where-Object { $_.RowKey -ne 'SharePointSiteListing-Count' })
        if (-not $SiteItems) {
            throw 'No SharePoint site listing data found in reporting database. Sync SharePointSiteUsage cache first.'
        }

        $UsageItems = @(Get-CIPPDbItem -TenantFilter $TenantFilter -Type 'SharePointSiteUsage' | Where-Object { $_.RowKey -ne 'SharePointSiteUsage-Count' })
        if (-not $UsageItems) {
            throw 'No SharePoint site usage data found in reporting database. Sync SharePointSiteUsage cache first.'
        }

        $LatestSiteTimestamp = ($SiteItems | Where-Object { $_.Timestamp } | Sort-Object Timestamp -Descending | Select-Object -First 1).Timestamp
        $LatestUsageTimestamp = ($UsageItems | Where-Object { $_.Timestamp } | Sort-Object Timestamp -Descending | Select-Object -First 1).Timestamp
        $CacheTimestamp = if ($LatestSiteTimestamp -and $LatestUsageTimestamp) {
            if ($LatestSiteTimestamp -gt $LatestUsageTimestamp) { $LatestSiteTimestamp } else { $LatestUsageTimestamp }
        } else {
            $LatestSiteTimestamp ?? $LatestUsageTimestamp
        }

        $UsageBySiteId = [System.Collections.Generic.Dictionary[string, object]]::new([System.StringComparer]::OrdinalIgnoreCase)
        foreach ($UsageItem in $UsageItems) {
            $UsageRow = $UsageItem.Data | ConvertFrom-Json -Depth 10
            if (-not [string]::IsNullOrWhiteSpace($UsageRow.siteId)) {
                $UsageBySiteId[[string]$UsageRow.siteId] = $UsageRow
            }
        }

        $Report = [System.Collections.Generic.List[PSCustomObject]]::new()
        foreach ($SiteItem in $SiteItems) {
            $Site = $SiteItem.Data | ConvertFrom-Json -Depth 10
            if ($Site.isPersonalSite -eq $true) {
                continue
            }

            $SiteUsage = $null
            [void]$UsageBySiteId.TryGetValue([string]$Site.sharepointIds.siteId, [ref]$SiteUsage)

            $StorageUsedInBytes = [double]($SiteUsage.storageUsedInBytes ?? 0)
            $StorageAllocatedInBytes = [double]($SiteUsage.storageAllocatedInBytes ?? 0)

            $ReportItem = [PSCustomObject]@{
                siteId                      = $Site.sharepointIds.siteId
                webId                       = $Site.sharepointIds.webId
                createdDateTime             = $Site.createdDateTime
                displayName                 = $Site.displayName
                webUrl                      = $Site.webUrl
                ownerDisplayName            = $SiteUsage.ownerDisplayName
                ownerPrincipalName          = $SiteUsage.ownerPrincipalName
                lastActivityDate            = $SiteUsage.lastActivityDate
                fileCount                   = $SiteUsage.fileCount
                storageUsedInGigabytes      = [math]::round($StorageUsedInBytes / 1GB, 2)
                storageAllocatedInGigabytes = [math]::round($StorageAllocatedInBytes / 1GB, 2)
                storageUsedInBytes          = $SiteUsage.storageUsedInBytes
                storageAllocatedInBytes     = $SiteUsage.storageAllocatedInBytes
                rootWebTemplate             = $SiteUsage.rootWebTemplate
                reportRefreshDate           = $SiteUsage.reportRefreshDate
                AutoMapUrl                  = $Site.AutoMapUrl
            }

            if ($CacheTimestamp) {
                $ReportItem | Add-Member -NotePropertyName 'CacheTimestamp' -NotePropertyValue $CacheTimestamp -Force
            }

            $Report.Add($ReportItem)
        }

        return $Report | Sort-Object -Property displayName

    } catch {
        Write-LogMessage -API 'SharePointSiteUsageReport' -tenant $TenantFilter -message "Failed to generate SharePoint site usage report: $($_.Exception.Message)" -sev Error -LogData (Get-CippException -Exception $_)
        throw
    }
}