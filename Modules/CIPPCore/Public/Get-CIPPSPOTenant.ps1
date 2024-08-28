function Get-CIPPSPOTenant {
    [CmdletBinding()]
    Param(
        [Parameter(Mandatory = $true)]
        [string]$TenantFilter,
        [string]$SharepointPrefix
    )

    if (!$SharepointPrefix) {
        # get sharepoint admin site
        $tenantName = (New-GraphGetRequest -uri 'https://graph.microsoft.com/beta/sites/root' -asApp $true -tenantid $TenantFilter).id.Split('.')[0]
    } else {
        $tenantName = $SharepointPrefix
    }
    $AdminUrl = "https://$($tenantName)-admin.sharepoint.com"

    # Query tenant settings
    $XML = @'
<Request AddExpandoFieldTypeSuffix="true" SchemaVersion="15.0.0.0" LibraryVersion="16.0.0.0" ApplicationName="SharePoint Online PowerShell (16.0.24908.0)" xmlns="http://schemas.microsoft.com/sharepoint/clientquery/2009"><Actions><ObjectPath Id="106" ObjectPathId="105" /><Query Id="107" ObjectPathId="105"><Query SelectAllProperties="true"><Properties /></Query></Query></Actions><ObjectPaths><Constructor Id="105" TypeId="{268004ae-ef6b-4e9b-8425-127220d84719}" /></ObjectPaths></Request>
'@
    $AdditionalHeaders = @{
        'Accept' = 'application/json;odata=verbose'
    }
    $Results = New-GraphPostRequest -scope "$AdminURL/.default" -tenantid $TenantFilter -Uri "$AdminURL/_vti_bin/client.svc/ProcessQuery" -Type POST -Body $XML -ContentType 'text/xml' -AddedHeaders $AdditionalHeaders

    $Results | Select-Object -Last 1 *, @{n = 'SharepointPrefix'; e = { $tenantName } }, @{n = 'TenantFilter'; e = { $TenantFilter } }
}
