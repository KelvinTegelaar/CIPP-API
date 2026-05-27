function Start-CIPPSiteVersionCleanup {
    <#
    .SYNOPSIS
    Start a file version batch delete job for a SharePoint site

    .DESCRIPTION
    Creates a new file version batch delete job via the CSOM NewFileVersionBatchDeleteJob method.
    This triggers cleanup of old file versions on a SharePoint site based on the specified parameters.

    .PARAMETER TenantFilter
    Tenant to run the cleanup on

    .PARAMETER SiteUrl
    Full URL of the SharePoint site to clean up

    .PARAMETER BatchDeleteMode
    Cleanup mode as an enum value:
        0 = DeleteOlderThanDays
        1 = CountLimits
        2 = SyncPolicy (apply the site's current version policy)

    .PARAMETER DeleteOlderThanDays
    Delete versions older than this many days. Use -1 to skip (when using SyncPolicy mode).

    .PARAMETER MajorVersionLimit
    Maximum major versions to keep. Use -1 to skip (when using SyncPolicy mode).

    .PARAMETER MajorWithMinorVersionsLimit
    Maximum major versions that retain minor versions. Use -1 to skip (when using SyncPolicy mode).

    .PARAMETER SyncListPolicy
    Whether to sync the list-level policy. Defaults to $false.

    .EXAMPLE
    # Sync site policy (apply current version settings to all existing versions)
    Start-CIPPSiteVersionCleanup -TenantFilter 'contoso.onmicrosoft.com' -SiteUrl 'https://contoso.sharepoint.com/sites/MySite' -BatchDeleteMode 2

    .EXAMPLE
    # Delete versions older than 365 days
    Start-CIPPSiteVersionCleanup -TenantFilter 'contoso.onmicrosoft.com' -SiteUrl 'https://contoso.sharepoint.com/sites/MySite' -BatchDeleteMode 0 -DeleteOlderThanDays 365

    .FUNCTIONALITY
    Internal

    #>
    [CmdletBinding(SupportsShouldProcess = $true)]
    param(
        [Parameter(Mandatory = $true)]
        [string]$TenantFilter,
        [Parameter(Mandatory = $true)]
        [string]$SiteUrl,
        [Parameter(Mandatory = $false)]
        [int]$BatchDeleteMode = 2,
        [Parameter(Mandatory = $false)]
        [int]$DeleteOlderThanDays = -1,
        [Parameter(Mandatory = $false)]
        [int]$MajorVersionLimit = -1,
        [Parameter(Mandatory = $false)]
        [int]$MajorWithMinorVersionsLimit = -1,
        [Parameter(Mandatory = $false)]
        [bool]$SyncListPolicy = $false
    )

    $SharePointInfo = Get-SharePointAdminLink -Public $false -tenantFilter $TenantFilter
    $AdminUrl = $SharePointInfo.AdminUrl
    $EscapedSiteUrl = [System.Security.SecurityElement]::Escape($SiteUrl)
    $SyncListPolicyValue = $SyncListPolicy.ToString().ToLower()

    $XML = @"
<Request AddExpandoFieldTypeSuffix="true" SchemaVersion="15.0.0.0" LibraryVersion="16.0.0.0" ApplicationName="SharePoint Online PowerShell (16.0.24908.0)" xmlns="http://schemas.microsoft.com/sharepoint/clientquery/2009"><Actions><ObjectPath Id="199" ObjectPathId="198" /><ObjectPath Id="201" ObjectPathId="200" /><Query Id="202" ObjectPathId="200"><Query SelectAllProperties="true"><Properties /></Query></Query></Actions><ObjectPaths><Constructor Id="198" TypeId="{268004ae-ef6b-4e9b-8425-127220d84719}" /><Method Id="200" ParentId="198" Name="NewFileVersionBatchDeleteJob"><Parameters><Parameter Type="String">$EscapedSiteUrl</Parameter><Parameter TypeId="{d1fd43d3-dba9-4d1c-bf13-d3894db255c7}"><Property Name="BatchDeleteMode" Type="Enum">$BatchDeleteMode</Property><Property Name="DeleteOlderThanDays" Type="Int32">$DeleteOlderThanDays</Property><Property Name="FileTypeSelections" Type="Null" /><Property Name="MajorVersionLimit" Type="Int32">$MajorVersionLimit</Property><Property Name="MajorWithMinorVersionsLimit" Type="Int32">$MajorWithMinorVersionsLimit</Property><Property Name="SyncListPolicy" Type="Boolean">$SyncListPolicyValue</Property></Parameter></Parameters></Method></ObjectPaths></Request>
"@

    $AdditionalHeaders = @{
        'Accept' = 'application/json;odata=verbose'
    }

    if ($PSCmdlet.ShouldProcess($SiteUrl, 'Start file version batch delete job')) {
        return New-GraphPostRequest -scope "$AdminUrl/.default" -tenantid $TenantFilter -Uri "$AdminUrl/_vti_bin/client.svc/ProcessQuery" -Type POST -Body $XML -ContentType 'text/xml' -AddedHeaders $AdditionalHeaders
    }
}
