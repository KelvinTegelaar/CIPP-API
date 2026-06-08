function Get-CIPPSPOSite {
    <#
    .SYNOPSIS
    Get SharePoint Site properties via CSOM

    .DESCRIPTION
    Retrieves all SharePoint site properties from the tenant using the CSOM GetSitePropertiesFromSharePoint method.
    Returns all site properties including version policy settings.

    .PARAMETER TenantFilter
    Tenant to query

    .EXAMPLE
    Get-CIPPSPOSite -TenantFilter 'contoso.onmicrosoft.com'

    .FUNCTIONALITY
    Internal

    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$TenantFilter
    )

    $SharePointInfo = Get-SharePointAdminLink -Public $false -tenantFilter $TenantFilter
    $AdminUrl = $SharePointInfo.AdminUrl

    $XML = @'
<Request AddExpandoFieldTypeSuffix="true" SchemaVersion="15.0.0.0" LibraryVersion="16.0.0.0" ApplicationName="SharePoint Online PowerShell (16.0.24908.0)" xmlns="http://schemas.microsoft.com/sharepoint/clientquery/2009"><Actions><ObjectPath Id="172" ObjectPathId="171" /><ObjectPath Id="174" ObjectPathId="173" /><Query Id="175" ObjectPathId="173"><Query SelectAllProperties="true"><Properties><Property Name="NextStartIndexFromSharePoint" ScalarProperty="true" /></Properties></Query><ChildItemQuery SelectAllProperties="true"><Properties /></ChildItemQuery></Query></Actions><ObjectPaths><Constructor Id="171" TypeId="{268004ae-ef6b-4e9b-8425-127220d84719}" /><Method Id="173" ParentId="171" Name="GetSitePropertiesFromSharePoint"><Parameters><Parameter Type="Null" /><Parameter Type="Boolean">false</Parameter></Parameters></Method></ObjectPaths></Request>
'@

    $AdditionalHeaders = @{
        'Accept' = 'application/json;odata=verbose'
    }

    $AllSites = [System.Collections.Generic.List[object]]::new()
    $StartIndex = $null

    do {
        if ($null -ne $StartIndex) {
            $XML = @"
<Request AddExpandoFieldTypeSuffix="true" SchemaVersion="15.0.0.0" LibraryVersion="16.0.0.0" ApplicationName="SharePoint Online PowerShell (16.0.24908.0)" xmlns="http://schemas.microsoft.com/sharepoint/clientquery/2009"><Actions><ObjectPath Id="172" ObjectPathId="171" /><ObjectPath Id="174" ObjectPathId="173" /><Query Id="175" ObjectPathId="173"><Query SelectAllProperties="true"><Properties><Property Name="NextStartIndexFromSharePoint" ScalarProperty="true" /></Properties></Query><ChildItemQuery SelectAllProperties="true"><Properties /></ChildItemQuery></Query></Actions><ObjectPaths><Constructor Id="171" TypeId="{268004ae-ef6b-4e9b-8425-127220d84719}" /><Method Id="173" ParentId="171" Name="GetSitePropertiesFromSharePoint"><Parameters><Parameter Type="String">$([System.Security.SecurityElement]::Escape($StartIndex))</Parameter><Parameter Type="Boolean">false</Parameter></Parameters></Method></ObjectPaths></Request>
"@
        }

        $Results = New-GraphPostRequest -scope "$AdminUrl/.default" -tenantid $TenantFilter -Uri "$AdminUrl/_vti_bin/client.svc/ProcessQuery" -Type POST -Body $XML -ContentType 'text/xml' -AddedHeaders $AdditionalHeaders

        # The response contains multiple objects; find the one with _Child_Items_ (site list) and NextStartIndexFromSharePoint
        $SiteCollection = $Results | Where-Object { $_._Child_Items_ }
        if ($SiteCollection) {
            foreach ($Site in $SiteCollection._Child_Items_) {
                [void]$AllSites.Add($Site)
            }
            $StartIndex = $SiteCollection.NextStartIndexFromSharePoint
        } else {
            $StartIndex = $null
        }
    } while ($StartIndex)

    return $AllSites
}
