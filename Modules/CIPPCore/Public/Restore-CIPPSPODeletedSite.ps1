function Restore-CIPPSPODeletedSite {
    <#
    .SYNOPSIS
    Restore a deleted SharePoint site from the tenant recycle bin via CSOM

    .DESCRIPTION
    Restores a deleted site collection using the CSOM RestoreDeletedSite method against the
    SharePoint admin endpoint (same ProcessQuery pattern as Set-CIPPSharePointPerms).

    .PARAMETER TenantFilter
    Tenant the site belongs to

    .PARAMETER SiteUrl
    Full URL of the deleted site to restore

    .EXAMPLE
    Restore-CIPPSPODeletedSite -TenantFilter 'contoso.onmicrosoft.com' -SiteUrl 'https://contoso.sharepoint.com/sites/OldSite'

    .FUNCTIONALITY
    Internal
    #>
    [CmdletBinding(SupportsShouldProcess = $true)]
    param(
        [Parameter(Mandatory = $true)]
        [string]$TenantFilter,
        [Parameter(Mandatory = $true)]
        [string]$SiteUrl
    )

    $SharePointInfo = Get-SharePointAdminLink -Public $false -tenantFilter $TenantFilter
    $AdminUrl = $SharePointInfo.AdminUrl
    $AdditionalHeaders = @{ 'Accept' = 'application/json;odata=verbose' }

    $XML = @"
<Request AddExpandoFieldTypeSuffix="true" SchemaVersion="15.0.0.0" LibraryVersion="16.0.0.0" ApplicationName="SharePoint Online PowerShell (16.0.24908.0)" xmlns="http://schemas.microsoft.com/sharepoint/clientquery/2009"><Actions><ObjectPath Id="2" ObjectPathId="1" /><ObjectPath Id="4" ObjectPathId="3" /><Query Id="5" ObjectPathId="3"><Query SelectAllProperties="false"><Properties><Property Name="IsComplete" ScalarProperty="true" /><Property Name="PollingInterval" ScalarProperty="true" /></Properties></Query></Query></Actions><ObjectPaths><Constructor Id="1" TypeId="{268004ae-ef6b-4e9b-8425-127220d84719}" /><Method Id="3" ParentId="1" Name="RestoreDeletedSite"><Parameters><Parameter Type="String">$([System.Security.SecurityElement]::Escape($SiteUrl))</Parameter></Parameters></Method></ObjectPaths></Request>
"@

    if ($PSCmdlet.ShouldProcess($SiteUrl, 'Restore deleted site')) {
        $Results = New-GraphPostRequest -scope "$AdminUrl/.default" -tenantid $TenantFilter -Uri "$AdminUrl/_vti_bin/client.svc/ProcessQuery" -Type POST -Body $XML -ContentType 'text/xml' -AddedHeaders $AdditionalHeaders

        $CsomError = ($Results | Where-Object { $_.ErrorInfo } | Select-Object -First 1).ErrorInfo.ErrorMessage
        if ($CsomError) { throw $CsomError }

        return ($Results | Where-Object { $null -ne $_.IsComplete } | Select-Object -First 1)
    }
}
