function Invoke-ListSiteStorageComposition {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        Sharepoint.Site.Read
    .DESCRIPTION
        Site-level storage composition at library ceiling: tip / previous-version estimate /
        recycle estimate from root web StorageMetrics + site StorageUsed. No file names.
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $APIName = $Request.Params.CIPPEndpoint
    $TenantFilter = $Request.Query.TenantFilter ?? $Request.Query.tenantFilter ?? $Request.Body.TenantFilter ?? $Request.Body.tenantFilter
    $SiteUrl = $Request.Query.SiteUrl ?? $Request.Body.SiteUrl

    function ConvertTo-StorageBytes {
        param($Raw)
        if ($null -eq $Raw -or $Raw -eq '') { return $null }
        $Clean = ([string]$Raw).Replace(',', '').Trim()
        if ($Clean -eq '') { return $null }
        try { return [int64][double]$Clean } catch { return $null }
    }

    try {
        if ([string]::IsNullOrWhiteSpace($TenantFilter)) { throw 'tenantFilter is required.' }
        if ([string]::IsNullOrWhiteSpace($SiteUrl)) { throw 'SiteUrl is required.' }

        $RestContext = Resolve-CIPPSharePointRestContext -TenantFilter $TenantFilter -SiteUrl $SiteUrl
        $SpoScope = $RestContext.Scope
        $JsonAccept = $RestContext.Headers
        $BaseUri = $RestContext.BaseUri

        $RootMetrics = New-GraphGetRequest -uri "$BaseUri/web/RootFolder?`$select=StorageMetrics&`$expand=StorageMetrics" -tenantid $TenantFilter -scope $SpoScope -extraHeaders $JsonAccept -UseCertificate -AsApp $true
        $TotalSize = ConvertTo-StorageBytes -Raw $RootMetrics.StorageMetrics.TotalSize
        $FileStreamSize = ConvertTo-StorageBytes -Raw $RootMetrics.StorageMetrics.TotalFileStreamSize
        $MetadataSize = ConvertTo-StorageBytes -Raw $RootMetrics.StorageMetrics.MetadataSize
        $FileCount = ConvertTo-StorageBytes -Raw $RootMetrics.StorageMetrics.TotalFileCount

        $Tip = if ($null -ne $FileStreamSize) { $FileStreamSize } else { [int64]0 }
        $Meta = if ($null -ne $MetadataSize) { $MetadataSize } else { [int64]0 }
        $Total = if ($null -ne $TotalSize) { $TotalSize } else { [int64]0 }
        $VersionEstimate = [Math]::Max([int64]0, $Total - $Tip - $Meta)

        $StorageUsed = $null
        try {
            $Usage = New-GraphGetRequest -uri "$BaseUri/site/Usage" -tenantid $TenantFilter -scope $SpoScope -extraHeaders $JsonAccept -UseCertificate -AsApp $true
            $StorageUsed = ConvertTo-StorageBytes -Raw $Usage.StorageUsageBytes
            if ($null -eq $StorageUsed) {
                $StorageUsed = ConvertTo-StorageBytes -Raw $Usage.StorageUsed
            }
        } catch {
            $StorageUsed = $null
        }
        if ($null -eq $StorageUsed) {
            try {
                $Web = New-GraphGetRequest -uri "$BaseUri/site?`$select=Usage" -tenantid $TenantFilter -scope $SpoScope -extraHeaders $JsonAccept -UseCertificate -AsApp $true
                $StorageUsed = ConvertTo-StorageBytes -Raw $Web.Usage.StorageUsedInBytes
            } catch {
                $StorageUsed = $null
            }
        }

        $RecycleEstimate = $null
        if ($null -ne $StorageUsed -and $null -ne $TotalSize) {
            $RecycleEstimate = [Math]::Max([int64]0, $StorageUsed - $TotalSize)
        }

        $Body = [PSCustomObject]@{
            siteUrl                 = $SiteUrl.TrimEnd('/')
            storageUsedInBytes      = $StorageUsed
            tipBytes                = $Tip
            metadataSizeInBytes     = $Meta
            totalSizeInBytes        = $Total
            versionEstimateBytes    = $VersionEstimate
            recycleEstimateBytes    = $RecycleEstimate
            fileCount               = $FileCount
            estimatesLabeled        = $true
        }
        $StatusCode = [HttpStatusCode]::OK
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        $Body = "Failed to get storage composition for $($SiteUrl): $($ErrorMessage.NormalizedError)"
        Write-LogMessage -Headers $Request.Headers -API $APIName -tenant $TenantFilter -message $Body -sev Error -LogData $ErrorMessage
        $StatusCode = [HttpStatusCode]::BadRequest
    }

    return ([HttpResponseContext]@{
            StatusCode = $StatusCode
            Body       = @{ Results = $Body }
        })
}
