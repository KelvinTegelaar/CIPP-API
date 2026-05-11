function Set-CIPPDBCacheSharePointSiteUsage {
    <#
    .SYNOPSIS
        Caches SharePoint site listing and site usage details for a tenant

    .PARAMETER TenantFilter
        The tenant to cache SharePoint site usage for

    .PARAMETER QueueId
        The queue ID to update with total tasks (optional)
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$TenantFilter,
        [string]$QueueId
    )

    try {
        Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message 'Caching SharePoint site listing and usage' -sev Debug

        $Tenant = Get-Tenants -TenantFilter $TenantFilter
        $TenantId = $Tenant.customerId

        $BulkRequests = @(
            @{
                id     = 'listAllSites'
                method = 'GET'
                url    = "sites/getAllSites?`$filter=isPersonalSite eq false&`$select=id,createdDateTime,description,name,displayName,isPersonalSite,lastModifiedDateTime,webUrl,siteCollection,sharepointIds&`$top=999"
            }
            @{
                id     = 'usage'
                method = 'GET'
                url    = "reports/getSharePointSiteUsageDetail(period='D7')?`$format=application/json&`$top=999"
            }
        )

        $Result = New-GraphBulkRequest -tenantid $TenantFilter -Requests @($BulkRequests) -asapp $true
        $Sites = @(($Result | Where-Object { $_.id -eq 'listAllSites' }).body.value)
        $UsageBase64 = ($Result | Where-Object { $_.id -eq 'usage' }).body
        $UsageJson = [System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String($UsageBase64))
        $UsageRows = @(($UsageJson | ConvertFrom-Json).value)

        # Ensure a stable row key for usage rows.
        foreach ($UsageRow in $UsageRows) {
            $UsageRow | Add-Member -NotePropertyName 'id' -NotePropertyValue $UsageRow.siteId -Force
        }

        $SiteListing = [System.Collections.Generic.List[object]]::new()
        foreach ($Site in $Sites) {
            $SiteListing.Add([PSCustomObject]@{
                    id              = $Site.id
                    sharepointIds   = $Site.sharepointIds
                    createdDateTime = $Site.createdDateTime
                    displayName     = $Site.displayName
                    webUrl          = $Site.webUrl
                    isPersonalSite  = $Site.isPersonalSite
                    AutoMapUrl      = ''
                })
        }

        $RequestId = 0
        $ListRequests = foreach ($Site in $SiteListing) {
            @{
                id     = $RequestId++
                method = 'GET'
                url    = "sites/$($Site.sharepointIds.siteId)/lists?`$select=id,name,list,parentReference"
            }
        }

        $LibraryLists = @()
        if ($ListRequests.Count -gt 0) {
            try {
                $LibraryLists = @((New-GraphBulkRequest -tenantid $TenantFilter -scope 'https://graph.microsoft.com/.default' -Requests @($ListRequests) -asapp $true).body.value | Where-Object { $_.list.template -eq 'DocumentLibrary' })
            } catch {
                Write-LogMessage -Message "Error getting auto map urls for SharePoint cache: $($_.Exception.Message)" -Sev 'Error' -tenant $TenantFilter -API 'CIPPDBCache' -LogData (Get-CippException -Exception $_)
            }
        }

        foreach ($Site in $SiteListing) {
            $ListId = ($LibraryLists | Where-Object { $_.parentReference.siteId -like "*$($Site.sharepointIds.siteId)*" } | Select-Object -First 1 -ExpandProperty id)
            $Site.AutoMapUrl = "tenantId=$($TenantId)&webId={$($Site.sharepointIds.webId)}&siteid={$($Site.sharepointIds.siteId)}&webUrl=$($Site.webUrl)&listId={$($ListId)}"
        }

        Add-CIPPDbItem -TenantFilter $TenantFilter -Type 'SharePointSiteListing' -Data @($SiteListing)
        Add-CIPPDbItem -TenantFilter $TenantFilter -Type 'SharePointSiteListing' -Data @($SiteListing) -Count

        Add-CIPPDbItem -TenantFilter $TenantFilter -Type 'SharePointSiteUsage' -Data @($UsageRows)
        Add-CIPPDbItem -TenantFilter $TenantFilter -Type 'SharePointSiteUsage' -Data @($UsageRows) -Count

        Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message 'Cached SharePoint site listing and usage successfully' -sev Debug

    } catch {
        Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message "Failed to cache SharePoint site usage: $($_.Exception.Message)" -sev Error -LogData (Get-CippException -Exception $_)
    }
}