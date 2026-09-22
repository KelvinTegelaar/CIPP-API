function Get-CIPPSPOSiteBulk {
    <#
    .SYNOPSIS
    Read individual SharePoint site properties for many sites (authoritative), batched and concurrent

    .DESCRIPTION
    Concurrent counterpart to Get-CIPPSPOSite -SiteUrl. Fires single-site GetSitePropertiesByUrl CSOM
    reads through CIPP.CIPPRestClient.SendConcurrent. Unlike the tenant-wide enumeration
    (GetSitePropertiesFromSharePoint), the single-site read is AUTHORITATIVE and immediate, and it is
    the ONLY source for ~19 per-site properties the enumeration returns as defaults (site owner,
    per-site sharing controls, ShowPeoplePickerSuggestionsForGuestUsers, ...).

    Reads are grouped: each request carries -BatchSize GetSitePropertiesByUrl reads in one ProcessQuery
    (fewer round-trips), and up to -MaxConcurrency requests run at once. SharePoint SERIALIZES the reads
    inside a request and rejects large ones ("The request uses too many resources"), so batches stay
    small; concurrency - not batch size - is what parallelises the work. The SPO admin token is
    acquired once and reused across every request.

    Returns one object per input URL: @{ SiteUrl; Site; Success; Error }, where Site is the parsed
    SiteProperties object (or $null on failure). A batch that fails marks every URL in it failed, so the
    caller can fall back per site.

    .PARAMETER TenantFilter
    Tenant to read from

    .PARAMETER SiteUrls
    Array of full site URLs to read.

    .PARAMETER MaxConcurrency
    Upper bound on in-flight requests (default 4). The SPO connection pool caps it to 5 regardless.

    .PARAMETER BatchSize
    Site reads packed into a single ProcessQuery (default 5). Kept small - SharePoint rejects large
    batched CSOM requests ("too many resources"); ~8 is the practical ceiling with SelectAllProperties.

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
        [int]$MaxConcurrency = 4,
        [int]$MaxRetries = 3,
        [int]$BatchSize = 5,
        [switch]$UseCertificate
    )

    $SharePointInfo = Get-SharePointAdminLink -Public $false -tenantFilter $TenantFilter
    $AdminUrl = $SharePointInfo.AdminUrl
    $RequestUri = "$AdminUrl/_vti_bin/client.svc/ProcessQuery"

    $TokenSplat = @{ tenantid = $TenantFilter; scope = "$AdminUrl/.default" }
    if ($UseCertificate) { $TokenSplat['AsApp'] = $true; $TokenSplat['UseCertificate'] = $true }
    $Authorization = (Get-GraphToken @TokenSplat).Authorization

    if ($BatchSize -lt 1) { $BatchSize = 1 }
    $CleanUrls = @($SiteUrls | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
    if ($CleanUrls.Count -eq 0) { return @() }

    $Requests = [System.Collections.Generic.List[CIPP.CIPPConcurrentRequest]]::new()
    $BatchUrls = [System.Collections.Generic.List[object]]::new()

    for ($Start = 0; $Start -lt $CleanUrls.Count; $Start += $BatchSize) {
        $End = [Math]::Min($Start + $BatchSize - 1, $CleanUrls.Count - 1)
        $Chunk = @($CleanUrls[$Start..$End])

        $Actions = [System.Text.StringBuilder]::new()
        $Paths = [System.Text.StringBuilder]::new()
        $Index = 0
        foreach ($Url in $Chunk) {
            $MethodId = 1000 + $Index; $PathId = 4000 + $Index; $QueryId = 7000 + $Index
            [void]$Actions.Append("<ObjectPath Id=`"$PathId`" ObjectPathId=`"$MethodId`" /><Query Id=`"$QueryId`" ObjectPathId=`"$MethodId`"><Query SelectAllProperties=`"true`"><Properties /></Query></Query>")
            [void]$Paths.Append("<Method Id=`"$MethodId`" ParentId=`"1`" Name=`"GetSitePropertiesByUrl`"><Parameters><Parameter Type=`"String`">$([System.Security.SecurityElement]::Escape($Url))</Parameter><Parameter Type=`"Boolean`">true</Parameter></Parameters></Method>")
            $Index++
        }
        $XML = "<Request AddExpandoFieldTypeSuffix=`"true`" SchemaVersion=`"15.0.0.0`" LibraryVersion=`"16.0.0.0`" ApplicationName=`"CIPP`" xmlns=`"http://schemas.microsoft.com/sharepoint/clientquery/2009`"><Actions>$($Actions.ToString())</Actions><ObjectPaths><Constructor Id=`"1`" TypeId=`"{268004ae-ef6b-4e9b-8425-127220d84719}`" />$($Paths.ToString())</ObjectPaths></Request>"

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
        $BatchUrls.Add($Chunk)
    }

    $Results = [CIPP.CIPPRestClient]::SendConcurrent($Requests, $MaxConcurrency, $MaxRetries)

    @(foreach ($Result in $Results) {
            $Chunk = $BatchUrls[$Result.Index]
            $BatchError = $null
            $Parsed = $null
            if ($Result.Error) {
                $BatchError = $Result.Error
            } elseif ($Result.StatusCode -ne 200) {
                $BatchError = "HTTP $($Result.StatusCode)"
            } else {
                try {
                    $Parsed = $Result.Result.Content | ConvertFrom-Json
                    # One action's error aborts the whole ProcessQuery, so a batch-level ErrorInfo fails
                    # every URL in the chunk - the caller falls back per site.
                    $CsomError = ($Parsed | Where-Object { $_.ErrorInfo } | Select-Object -First 1).ErrorInfo.ErrorMessage
                    if ($CsomError) { $BatchError = $CsomError }
                } catch {
                    $BatchError = "Could not parse CSOM response: $($_.Exception.Message)"
                }
            }

            if ($BatchError) {
                foreach ($Url in $Chunk) {
                    [PSCustomObject]@{ SiteUrl = $Url; Site = $null; Success = $false; Error = $BatchError }
                }
            } else {
                # Match each returned SiteProperties to its input URL (order is not guaranteed, and a
                # deleted/erroring site in the middle would leave a gap) rather than trusting position.
                $SitesInBatch = @($Parsed | Where-Object { $_._ObjectType_ -match 'SiteProperties' -and $_.Url })
                foreach ($Url in $Chunk) {
                    $Site = $SitesInBatch | Where-Object { "$($_.Url)".TrimEnd('/') -ieq "$Url".TrimEnd('/') } | Select-Object -First 1
                    if ($Site) {
                        [PSCustomObject]@{ SiteUrl = $Url; Site = $Site; Success = $true; Error = $null }
                    } else {
                        [PSCustomObject]@{ SiteUrl = $Url; Site = $null; Success = $false; Error = 'No SiteProperties returned' }
                    }
                }
            }
        })
}
