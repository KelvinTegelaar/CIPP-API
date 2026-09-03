function Get-CIPPSPOSiteBulk {
    <#
    .SYNOPSIS
    Read individual SharePoint site properties for many sites concurrently (authoritative)

    .DESCRIPTION
    Concurrent counterpart to Get-CIPPSPOSite -SiteUrl. Fires one single-site GetSitePropertiesByUrl
    CSOM read per URL through CIPP.CIPPRestClient.SendConcurrent. Unlike the bulk site enumeration
    (GetSitePropertiesFromSharePoint), the single-site read is AUTHORITATIVE and immediate - it
    reflects writes right away - so this is what to use to verify a just-applied change, never the
    lagging enumerate. The SPO admin token is acquired once and reused across every request.

    Returns one object per URL: @{ SiteUrl; Site; Success; Error }, where Site is the parsed
    SiteProperties object (or $null on failure), in the same order as the input.

    .PARAMETER TenantFilter
    Tenant to read from

    .PARAMETER SiteUrls
    Array of full site URLs to read.

    .PARAMETER MaxConcurrency
    Upper bound on in-flight requests (default 8); the SPO connection pool caps it to 10 regardless.

    .PARAMETER UseCertificate
    Authenticate app-only with the SAM certificate (SharePoint app-only requires it).

    .FUNCTIONALITY
    Internal
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$TenantFilter,
        [Parameter(Mandatory = $true)]
        [string[]]$SiteUrls,
        [int]$MaxConcurrency = 8,
        [int]$MaxRetries = 3,
        [switch]$UseCertificate
    )

    $SharePointInfo = Get-SharePointAdminLink -Public $false -tenantFilter $TenantFilter
    $AdminUrl = $SharePointInfo.AdminUrl
    $RequestUri = "$AdminUrl/_vti_bin/client.svc/ProcessQuery"

    $TokenSplat = @{ tenantid = $TenantFilter; scope = "$AdminUrl/.default" }
    if ($UseCertificate) { $TokenSplat['AsApp'] = $true; $TokenSplat['UseCertificate'] = $true }
    $Authorization = (Get-GraphToken @TokenSplat).Authorization

    $Requests = [System.Collections.Generic.List[CIPP.CIPPConcurrentRequest]]::new()
    $RequestUrls = [System.Collections.Generic.List[string]]::new()
    foreach ($Url in $SiteUrls) {
        if ([string]::IsNullOrWhiteSpace($Url)) { continue }
        $XML = @"
<Request AddExpandoFieldTypeSuffix="true" SchemaVersion="15.0.0.0" LibraryVersion="16.0.0.0" ApplicationName="SharePoint Online PowerShell (16.0.24908.0)" xmlns="http://schemas.microsoft.com/sharepoint/clientquery/2009"><Actions><ObjectPath Id="2" ObjectPathId="1" /><ObjectPath Id="4" ObjectPathId="3" /><Query Id="5" ObjectPathId="3"><Query SelectAllProperties="true"><Properties /></Query></Query></Actions><ObjectPaths><Constructor Id="1" TypeId="{268004ae-ef6b-4e9b-8425-127220d84719}" /><Method Id="3" ParentId="1" Name="GetSitePropertiesByUrl"><Parameters><Parameter Type="String">$([System.Security.SecurityElement]::Escape($Url))</Parameter><Parameter Type="Boolean">true</Parameter></Parameters></Method></ObjectPaths></Request>
"@
        $Request = [CIPP.CIPPConcurrentRequest]::new()
        $Request.Uri = $RequestUri
        $Request.Method = 'POST'
        $Request.Body = $XML
        $Request.ContentType = 'text/xml'
        $Headers = [System.Collections.Generic.Dictionary[string, string]]::new()
        $Headers['Authorization'] = $Authorization
        $Headers['Accept'] = 'application/json;odata=verbose'
        $Request.Headers = $Headers

        $Requests.Add($Request)
        $RequestUrls.Add($Url)
    }

    if ($Requests.Count -eq 0) { return @() }

    $Results = [CIPP.CIPPRestClient]::SendConcurrent($Requests, $MaxConcurrency, $MaxRetries)

    @(foreach ($Result in $Results) {
            $Url = $RequestUrls[$Result.Index]
            $Site = $null
            $ErrorMessage = $null
            if ($Result.Error) {
                $ErrorMessage = $Result.Error
            } elseif ($Result.StatusCode -ne 200) {
                $ErrorMessage = "HTTP $($Result.StatusCode)"
            } else {
                try {
                    $Parsed = $Result.Result.Content | ConvertFrom-Json
                    $CsomError = ($Parsed | Where-Object { $_.ErrorInfo } | Select-Object -First 1).ErrorInfo.ErrorMessage
                    if ($CsomError) {
                        $ErrorMessage = $CsomError
                    } else {
                        $Site = $Parsed | Where-Object { $_._ObjectType_ -match 'SiteProperties' } | Select-Object -First 1
                        if (-not $Site) { $ErrorMessage = 'No SiteProperties returned' }
                    }
                } catch {
                    $ErrorMessage = "Could not parse CSOM response: $($_.Exception.Message)"
                }
            }
            [PSCustomObject]@{
                SiteUrl = $Url
                Site    = $Site
                Success = [string]::IsNullOrEmpty($ErrorMessage)
                Error   = $ErrorMessage
            }
        })
}
