function Get-CIPPSPOTenant {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$TenantFilter,
        [string]$SharepointPrefix,
        [switch]$SkipCache
    )

    if (!$SharepointPrefix) {
        # get sharepoint admin site
        $SharePointInfo = Get-SharePointAdminLink -Public $false -tenantFilter $TenantFilter
        $tenantName = $SharePointInfo.TenantName
        $AdminUrl = $SharePointInfo.AdminUrl
    } else {
        $tenantName = $SharepointPrefix
        $AdminUrl = "https://$($tenantName)-admin.sharepoint.com"
    }

    $Table = Get-CIPPTable -tablename 'cachespotenant'
    $Filter = "PartitionKey eq 'Tenant' and RowKey eq '$TenantFilter' and Timestamp gt datetime'$( (Get-Date).AddHours(-1).ToString('yyyy-MM-ddTHH:mm:ssZ') )'"
    if (!$SkipCache.IsPresent) {
        $CachedTenant = Get-CIPPAzDataTableEntity @Table -Filter $Filter
        if ($CachedTenant -and (Test-Json $CachedTenant.JSON)) {
            $Results = $CachedTenant.JSON | ConvertFrom-Json
            return $Results
        }
    }

    # Query tenant settings
    $XML = @'
<Request AddExpandoFieldTypeSuffix="true" SchemaVersion="15.0.0.0" LibraryVersion="16.0.0.0" ApplicationName="SharePoint Online PowerShell (16.0.24908.0)" xmlns="http://schemas.microsoft.com/sharepoint/clientquery/2009"><Actions><ObjectPath Id="106" ObjectPathId="105" /><Query Id="107" ObjectPathId="105"><Query SelectAllProperties="true"><Properties /></Query></Query></Actions><ObjectPaths><Constructor Id="105" TypeId="{268004ae-ef6b-4e9b-8425-127220d84719}" /></ObjectPaths></Request>
'@
    $AdditionalHeaders = @{
        'Accept' = 'application/json;odata=verbose'
    }

    $Results = New-GraphPostRequest -scope "$($AdminUrl)/.default" -tenantid $TenantFilter -Uri "$($SharePointInfo.AdminUrl)/_vti_bin/client.svc/ProcessQuery" -Type POST -Body $XML -ContentType 'text/xml' -AddedHeaders $AdditionalHeaders

    $Results = $Results | Select-Object -Last 1 *, @{n = 'SharepointPrefix'; e = { $tenantName } }, @{n = 'TenantFilter'; e = { $TenantFilter } }

    # Cache result
    $Entity = @{
        PartitionKey = 'Tenant'
        RowKey       = $TenantFilter
        JSON         = [string]($Results | ConvertTo-Json -Depth 10 -Compress)
    }
    Add-CIPPAzDataTableEntity @Table -Entity $Entity -Force
    return $Results
}
