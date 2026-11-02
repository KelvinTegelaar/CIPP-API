function Get-CIPPSPODeletedSites {
    <#
    .SYNOPSIS
    List deleted SharePoint sites (tenant recycle bin) via CSOM

    .DESCRIPTION
    Retrieves the deleted site collections still restorable from the SharePoint tenant recycle
    bin using the CSOM GetDeletedSitePropertiesFromSharePoint method, following the same paging
    pattern as Get-CIPPSPOSite.

    .PARAMETER TenantFilter
    Tenant to query

    .EXAMPLE
    Get-CIPPSPODeletedSites -TenantFilter 'contoso.onmicrosoft.com'

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
    $AdditionalHeaders = @{ 'Accept' = 'application/json;odata=verbose' }

    $AllSites = [System.Collections.Generic.List[object]]::new()
    $StartIndex = $null

    do {
        $StartIndexParameter = if ($null -ne $StartIndex) {
            "<Parameter Type=`"String`">$([System.Security.SecurityElement]::Escape($StartIndex))</Parameter>"
        } else {
            '<Parameter Type="Null" />'
        }
        $XML = @"
<Request AddExpandoFieldTypeSuffix="true" SchemaVersion="15.0.0.0" LibraryVersion="16.0.0.0" ApplicationName="SharePoint Online PowerShell (16.0.24908.0)" xmlns="http://schemas.microsoft.com/sharepoint/clientquery/2009"><Actions><ObjectPath Id="172" ObjectPathId="171" /><ObjectPath Id="174" ObjectPathId="173" /><Query Id="175" ObjectPathId="173"><Query SelectAllProperties="true"><Properties><Property Name="NextStartIndexFromSharePoint" ScalarProperty="true" /></Properties></Query><ChildItemQuery SelectAllProperties="true"><Properties /></ChildItemQuery></Query></Actions><ObjectPaths><Constructor Id="171" TypeId="{268004ae-ef6b-4e9b-8425-127220d84719}" /><Method Id="173" ParentId="171" Name="GetDeletedSitePropertiesFromSharePoint"><Parameters>$StartIndexParameter</Parameters></Method></ObjectPaths></Request>
"@

        $Results = New-GraphPostRequest -scope "$AdminUrl/.default" -tenantid $TenantFilter -Uri "$AdminUrl/_vti_bin/client.svc/ProcessQuery" -Type POST -Body $XML -ContentType 'text/xml' -AddedHeaders $AdditionalHeaders

        $CsomError = ($Results | Where-Object { $_.ErrorInfo } | Select-Object -First 1).ErrorInfo.ErrorMessage
        if ($CsomError) { throw $CsomError }

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
