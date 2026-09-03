function Set-CIPPSPOSiteBulk {
    <#
    .SYNOPSIS
    Set properties on many SharePoint sites concurrently via CSOM

    .DESCRIPTION
    Batched counterpart to Set-CIPPSPOSite. SharePoint executes each site's Update serially inside a
    single ProcessQuery (and caps a few per request), so batching into one request gives no speedup;
    the win is CONCURRENCY. This builds one per-site ProcessQuery (identical shape to Set-CIPPSPOSite)
    and hands them all to CIPP.CIPPRestClient.SendConcurrent, which fans them out asynchronously in
    .NET (bounded by MaxConcurrency and the SPO admin host's connection-pool cap) with Retry-After /
    backoff on 429. The SPO admin token is acquired once and reused across every request.

    Returns one object per site: @{ SiteUrl; Success; Error }. A single site's failure never aborts
    the batch.

    .PARAMETER TenantFilter
    Tenant to apply settings to

    .PARAMETER Sites
    Array of per-site specs, each @{ SiteUrl = '<url>'; Properties = @{ <name> = <value>; ... } }.
    Supported value types match Set-CIPPSPOSite: Boolean, String, Int32, Int64, and the CSOM enum
    properties (SharingCapability, DefaultSharingLinkType, DefaultLinkPermission,
    SharingDomainRestrictionMode, ConditionalAccessPolicy).

    .PARAMETER MaxConcurrency
    Upper bound on in-flight requests (default 8). The SPO admin connection pool caps effective
    concurrency to that host regardless, which keeps this under SharePoint's throttle threshold.

    .PARAMETER UseCertificate
    Authenticate app-only with the SAM certificate (SharePoint app-only requires it).

    .FUNCTIONALITY
    Internal
    #>
    [CmdletBinding(SupportsShouldProcess = $true)]
    param(
        [Parameter(Mandatory = $true)]
        [string]$TenantFilter,
        [Parameter(Mandatory = $true)]
        [array]$Sites,
        [int]$MaxConcurrency = 8,
        [int]$MaxRetries = 3,
        [switch]$UseCertificate
    )

    $SharePointInfo = Get-SharePointAdminLink -Public $false -tenantFilter $TenantFilter
    $AdminUrl = $SharePointInfo.AdminUrl
    $RequestUri = "$AdminUrl/_vti_bin/client.svc/ProcessQuery"

    # Acquire the SPO admin token ONCE and reuse it across every concurrent request.
    $TokenSplat = @{ tenantid = $TenantFilter; scope = "$AdminUrl/.default" }
    if ($UseCertificate) { $TokenSplat['AsApp'] = $true; $TokenSplat['UseCertificate'] = $true }
    $Authorization = (Get-GraphToken @TokenSplat).Authorization

    $AllowedTypes = @('Boolean', 'String', 'Int32', 'Int64')
    $EnumProperties = @('SharingCapability', 'DefaultSharingLinkType', 'DefaultLinkPermission', 'SharingDomainRestrictionMode', 'ConditionalAccessPolicy')

    $Requests = [System.Collections.Generic.List[CIPP.CIPPConcurrentRequest]]::new()
    $RequestSites = [System.Collections.Generic.List[object]]::new()

    foreach ($Site in $Sites) {
        if ([string]::IsNullOrWhiteSpace($Site.SiteUrl) -or -not $Site.Properties) { continue }

        $SetProperty = [System.Collections.Generic.List[string]]::new()
        $x = 106
        foreach ($Property in $Site.Properties.Keys) {
            $Value = $Site.Properties[$Property]
            $PropertyType = $Value.GetType().Name
            if ($Property -in $EnumProperties) {
                $SetProperty.Add("<SetProperty Id=`"$x`" ObjectPathId=`"104`" Name=`"$Property`"><Parameter Type=`"Enum`">$([int]$Value)</Parameter></SetProperty>")
                $x++
            } elseif ($PropertyType -in $AllowedTypes) {
                $PropertyToSet = if ($PropertyType -eq 'Boolean') { $Value.ToString().ToLower() } else { [System.Security.SecurityElement]::Escape([string]$Value) }
                $SetProperty.Add("<SetProperty Id=`"$x`" ObjectPathId=`"104`" Name=`"$Property`"><Parameter Type=`"$PropertyType`">$PropertyToSet</Parameter></SetProperty>")
                $x++
            }
        }
        if ($SetProperty.Count -eq 0) { continue }

        $XML = @"
<Request AddExpandoFieldTypeSuffix="true" SchemaVersion="15.0.0.0" LibraryVersion="16.0.0.0" ApplicationName="SharePoint Online PowerShell (16.0.24908.0)" xmlns="http://schemas.microsoft.com/sharepoint/clientquery/2009"><Actions>$($SetProperty -join '')<ObjectPath Id="$x" ObjectPathId="113" /><ObjectIdentityQuery Id="$($x + 1)" ObjectPathId="104" /></Actions><ObjectPaths><Method Id="104" ParentId="102" Name="GetSitePropertiesByUrl"><Parameters><Parameter Type="String">$([System.Security.SecurityElement]::Escape($Site.SiteUrl))</Parameter><Parameter Type="Boolean">false</Parameter></Parameters></Method><Method Id="113" ParentId="104" Name="Update" /><Constructor Id="102" TypeId="{268004ae-ef6b-4e9b-8425-127220d84719}" /></ObjectPaths></Request>
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
        $RequestSites.Add($Site)
    }

    if ($Requests.Count -eq 0) { return @() }

    if (-not $PSCmdlet.ShouldProcess("$($Requests.Count) sites", 'Set Site Properties (bulk)')) { return @() }

    $Results = [CIPP.CIPPRestClient]::SendConcurrent($Requests, $MaxConcurrency, $MaxRetries)

    @(foreach ($Result in $Results) {
            $Site = $RequestSites[$Result.Index]
            $ErrorMessage = $null
            if ($Result.Error) {
                $ErrorMessage = $Result.Error
            } elseif ($Result.StatusCode -ne 200) {
                $ErrorMessage = "HTTP $($Result.StatusCode): $($Result.Result.Content)"
            } else {
                # CSOM returns 200 even for per-site failures; the error is in the body's ErrorInfo.
                try {
                    $CsomError = ($Result.Result.Content | ConvertFrom-Json | Where-Object { $_.ErrorInfo } | Select-Object -First 1).ErrorInfo.ErrorMessage
                    if ($CsomError) { $ErrorMessage = $CsomError }
                } catch {
                    $ErrorMessage = "Could not parse CSOM response: $($_.Exception.Message)"
                }
            }
            [PSCustomObject]@{
                SiteUrl = $Site.SiteUrl
                Success = [string]::IsNullOrEmpty($ErrorMessage)
                Error   = $ErrorMessage
            }
        })
}
