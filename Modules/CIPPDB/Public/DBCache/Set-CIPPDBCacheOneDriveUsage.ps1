function Set-CIPPDBCacheOneDriveUsage {
    <#
    .SYNOPSIS
        Caches OneDrive usage details for a tenant

    .PARAMETER TenantFilter
        The tenant to cache OneDrive usage for

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
        Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message 'Caching OneDrive site listing and usage' -sev Debug

        $BulkRequests = @(
            @{
                id     = 'listAllSites'
                method = 'GET'
                url    = "sites/getAllSites?`$filter=isPersonalSite eq true&`$select=id,createdDateTime,description,name,displayName,isPersonalSite,lastModifiedDateTime,webUrl,siteCollection,sharepointIds&`$top=999"
            }
            @{
                id     = 'usage'
                method = 'GET'
                url    = "reports/getOneDriveUsageAccountDetail(period='D7')?`$format=application/json&`$top=999"
            }
        )

        $Result = New-GraphBulkRequest -tenantid $TenantFilter -Requests @($BulkRequests) -asapp $true
        $Sites = @(($Result | Where-Object { $_.id -eq 'listAllSites' }).body.value)

        $UsageResponse = $Result | Where-Object { $_.id -eq 'usage' }
        if ($UsageResponse.status -and $UsageResponse.status -ne 200) {
            throw ($UsageResponse.body.error.message ?? "Usage report request failed with status $($UsageResponse.status)")
        }
        $UsageBody = $UsageResponse.body
        if ($UsageBody -is [string]) {
            $UsageJson = [System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String($UsageBody))
            $OneDriveUsage = @(($UsageJson | ConvertFrom-Json).value)
        } else {
            $OneDriveUsage = @($UsageBody.value)
        }

        foreach ($UsageRow in $OneDriveUsage) {
            if ($null -eq $UsageRow) { continue }
            $UsageRow | Add-Member -NotePropertyName 'id' -NotePropertyValue $UsageRow.siteId -Force
            $UsageRow | Add-Member -NotePropertyName 'userPrincipalName' -NotePropertyValue $UsageRow.ownerPrincipalName -Force
        }

        $OneDriveListing = [System.Collections.Generic.List[object]]::new()
        foreach ($Site in $Sites) {
            $OneDriveListing.Add([PSCustomObject]@{
                    id              = $Site.id
                    sharepointIds   = $Site.sharepointIds
                    createdDateTime = $Site.createdDateTime
                    displayName     = $Site.displayName
                    webUrl          = $Site.webUrl
                    isPersonalSite  = $Site.isPersonalSite
                    AutoMapUrl      = ''
                })
        }

        Add-CIPPDbItem -TenantFilter $TenantFilter -Type 'OneDriveSiteListing' -Data @($OneDriveListing) -AddCount

        Add-CIPPDbItem -TenantFilter $TenantFilter -Type 'OneDriveUsage' -Data @($OneDriveUsage) -AddCount

        Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message 'Cached OneDrive site listing and usage successfully' -sev Debug

    } catch {
        Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message "Failed to cache OneDrive usage: $($_.Exception.Message)" -sev Error
    }
}
