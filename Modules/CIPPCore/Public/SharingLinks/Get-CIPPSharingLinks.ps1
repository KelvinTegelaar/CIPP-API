function Get-CIPPSharingLinks {
    <#
    .SYNOPSIS
        A tenant's cached SharePoint and OneDrive sharing links, from the CippSharingLinks table.
    .DESCRIPTION
        Rows are written by the sharing-links scan (Push-DBCacheSharePointSiteSharingLinks) and kept
        until a scan proves the link gone; roles and sharedWith are stored as JSON arrays.
    .FUNCTIONALITY
        Internal
    #>
    param([Parameter(Mandatory = $true)][string]$TenantFilter)

    $TenantFilter = @(Get-Tenants -TenantFilter $TenantFilter -IncludeErrors)[0].defaultDomainName ?? $TenantFilter
    $SafeTenant = ConvertTo-CIPPODataFilterValue -Value $TenantFilter -Type String
    $Table = Get-CippTable -tablename 'CippSharingLinks'
    foreach ($Row in @(Get-CIPPAzDataTableEntity @Table -Filter "PartitionKey eq '$SafeTenant'")) {
        [PSCustomObject]@{
            id                   = $Row.id
            siteId               = $Row.siteId
            siteName             = $Row.siteName
            siteUrl              = $Row.siteUrl
            workload             = $Row.workload
            driveId              = $Row.driveId
            driveName            = $Row.driveName
            itemId               = $Row.itemId
            fileName             = $Row.fileName
            itemUrl              = $Row.itemUrl
            itemType             = $Row.itemType
            size                 = $Row.size
            lastModifiedDateTime = $Row.lastModifiedDateTime
            permissionId         = $Row.permissionId
            linkType             = $Row.linkType
            linkScope            = $Row.linkScope
            classification       = $Row.classification
            roles                = @(if ($Row.roles) { [CIPP.CippJson]::ConvertFromJson([string]$Row.roles) })
            sharedWith           = @(if ($Row.sharedWith) { [CIPP.CippJson]::ConvertFromJson([string]$Row.sharedWith) })
            linkUrl              = $Row.linkUrl
            hasPassword          = [bool]$Row.hasPassword
            expirationDateTime   = $Row.expirationDateTime
        }
    }
}
