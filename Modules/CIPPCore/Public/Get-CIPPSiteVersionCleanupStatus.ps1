function Get-CIPPSiteVersionCleanupStatus {
    <#
    .SYNOPSIS
    Get the progress of a file version batch delete (trim) job for a SharePoint site

    .DESCRIPTION
    Queries the progress of the file version batch delete job for a SharePoint site via the
    CSOM GetFileVersionBatchDeleteJobProgress method on the Tenant object, using the same
    ProcessQuery channel as Start-CIPPSiteVersionCleanup. Reports the status of a cleanup
    previously started with Start-CIPPSiteVersionCleanup.

    Unlike NewFileVersionBatchDeleteJob / RemoveFileVersionBatchDeleteJob (which return an
    SpoOperation object that the client serialises with a <Query SelectAllProperties="true">),
    GetFileVersionBatchDeleteJobProgress returns a plain String whose content is a JSON blob.
    It is therefore invoked as a bare <Method> inside <Actions> with no <Query> wrapper - asking
    for SelectAllProperties on a String fails server-side with "Cannot find stub for type
    System.String". The ProcessQuery response is an array whose only String element is the JSON
    progress payload, which this function parses and returns. (Confirmed against a captured
    Get-SPOSiteFileVersionBatchDeleteJobProgress request.)

    .PARAMETER TenantFilter
    Tenant to query

    .PARAMETER SiteUrl
    Full URL of the SharePoint site to query

    .EXAMPLE
    Get-CIPPSiteVersionCleanupStatus -TenantFilter 'contoso.onmicrosoft.com' -SiteUrl 'https://contoso.sharepoint.com/sites/MySite'

    .FUNCTIONALITY
    Internal

    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$TenantFilter,
        [Parameter(Mandatory = $true)]
        [string]$SiteUrl
    )

    $SharePointInfo = Get-SharePointAdminLink -Public $false -tenantFilter $TenantFilter
    $AdminUrl = $SharePointInfo.AdminUrl
    $EscapedSiteUrl = [System.Security.SecurityElement]::Escape($SiteUrl)

    # CSOM pattern: Tenant Constructor -> GetFileVersionBatchDeleteJobProgress(siteUrl).
    # The method returns a String (JSON), so it is called directly in <Actions> with no <Query>.
    $XML = @"
<Request AddExpandoFieldTypeSuffix="true" SchemaVersion="15.0.0.0" LibraryVersion="16.0.0.0" ApplicationName="SharePoint Online PowerShell (16.0.24908.0)" xmlns="http://schemas.microsoft.com/sharepoint/clientquery/2009"><Actions><ObjectPath Id="40" ObjectPathId="39" /><Method Name="GetFileVersionBatchDeleteJobProgress" Id="41" ObjectPathId="39"><Parameters><Parameter Type="String">$EscapedSiteUrl</Parameter></Parameters></Method></Actions><ObjectPaths><Constructor Id="39" TypeId="{268004ae-ef6b-4e9b-8425-127220d84719}" /></ObjectPaths></Request>
"@

    $AdditionalHeaders = @{
        'Accept' = 'application/json;odata=verbose'
    }

    $Response = New-GraphPostRequest -scope "$AdminUrl/.default" -tenantid $TenantFilter -Uri "$AdminUrl/_vti_bin/client.svc/ProcessQuery" -Type POST -Body $XML -ContentType 'text/xml' -AddedHeaders $AdditionalHeaders

    # ProcessQuery returns a JSON array; if it came back as raw text, parse it first.
    if ($Response -is [string]) {
        $Response = $Response | ConvertFrom-Json
    }

    # The first array element carries ErrorInfo for the whole request.
    $ErrorInfo = $Response | Where-Object { $_.PSObject.Properties.Name -contains 'ErrorInfo' } | Select-Object -First 1
    if ($ErrorInfo.ErrorInfo) {
        throw "SharePoint returned an error querying version cleanup status for $SiteUrl : $($ErrorInfo.ErrorInfo.ErrorMessage)"
    }

    # GetFileVersionBatchDeleteJobProgress returns its payload as the only String element.
    $ProgressJson = $Response | Where-Object { $_ -is [string] } | Select-Object -First 1

    if ([string]::IsNullOrWhiteSpace($ProgressJson)) {
        return [PSCustomObject]@{
            SiteUrl = $SiteUrl
            Status  = 'NoJob'
            Message = 'No file version batch delete job found for this site.'
        }
    }

    $Progress = $ProgressJson | ConvertFrom-Json
    Add-Member -InputObject $Progress -MemberType NoteProperty -Name 'SiteUrl' -Value $SiteUrl -Force
    return $Progress
}
