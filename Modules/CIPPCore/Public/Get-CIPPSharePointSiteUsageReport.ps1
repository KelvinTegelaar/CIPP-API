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
            $AllSiteItems = @(Get-CIPPDbItem -TenantFilter 'allTenants' -Type 'SharePointSiteListing' | Where-Object { $_.RowKey -ne 'SharePointSiteListing-Count' })
            $AllUsageItems = @(Get-CIPPDbItem -TenantFilter 'allTenants' -Type 'SharePointSiteUsage' | Where-Object { $_.RowKey -ne 'SharePointSiteUsage-Count' })

            $TenantList = Get-Tenants -IncludeErrors
            $ValidTenants = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
            foreach ($T in $TenantList) { [void]$ValidTenants.Add($T.defaultDomainName) }

            $UsageBySiteId = [System.Collections.Generic.Dictionary[string, object]]::new([System.StringComparer]::OrdinalIgnoreCase)
            foreach ($UsageItem in $AllUsageItems) {
                $UsageRow = $UsageItem.Data | ConvertFrom-Json -Depth 10
                if (-not [string]::IsNullOrWhiteSpace($UsageRow.siteId)) {
                    $UsageBySiteId[[string]$UsageRow.siteId.Trim('{}')] = $UsageRow
                }
            }

            $AllResults = [System.Collections.Generic.List[PSCustomObject]]::new()
            foreach ($SiteItem in $AllSiteItems) {
                $Tenant = $SiteItem.PartitionKey
                if (-not $ValidTenants.Contains($Tenant)) { continue }

                $Site = $SiteItem.Data | ConvertFrom-Json -Depth 10
                if ($Site.isPersonalSite -eq $true) { continue }

                $SiteUsage = $null
                [void]$UsageBySiteId.TryGetValue([string]$Site.sharepointIds.siteId.Trim('{}'), [ref]$SiteUsage)

                $AllResults.Add((ConvertTo-CIPPSharePointSiteUsagePayload -Site $Site -SiteUsage $SiteUsage -Tenant $Tenant))
            }
            return $AllResults
        }

        $SiteItems = @(Get-CIPPDbItem -TenantFilter $TenantFilter -Type 'SharePointSiteListing' | Where-Object { $_.RowKey -ne 'SharePointSiteListing-Count' })
        if (-not $SiteItems) {
            throw 'No SharePoint site listing data found in reporting database. Sync SharePointSiteUsage cache first.'
        }

        $UsageItems = @(Get-CIPPDbItem -TenantFilter $TenantFilter -Type 'SharePointSiteUsage' | Where-Object { $_.RowKey -ne 'SharePointSiteUsage-Count' })

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
                $UsageBySiteId[[string]$UsageRow.siteId.Trim('{}')] = $UsageRow
            }
        }

        $Report = [System.Collections.Generic.List[PSCustomObject]]::new()
        foreach ($SiteItem in $SiteItems) {
            $Site = $SiteItem.Data | ConvertFrom-Json -Depth 10
            if ($Site.isPersonalSite -eq $true) {
                continue
            }

            $SiteUsage = $null
            [void]$UsageBySiteId.TryGetValue([string]$Site.sharepointIds.siteId.Trim('{}'), [ref]$SiteUsage)

            $Report.Add((ConvertTo-CIPPSharePointSiteUsagePayload -Site $Site -SiteUsage $SiteUsage -CacheTimestamp $CacheTimestamp))
        }

        return $Report | Sort-Object -Property displayName

    } catch {
        Write-LogMessage -API 'SharePointSiteUsageReport' -tenant $TenantFilter -message "Failed to generate SharePoint site usage report: $($_.Exception.Message)" -sev Error -LogData (Get-CippException -Exception $_)
        throw
    }
}
