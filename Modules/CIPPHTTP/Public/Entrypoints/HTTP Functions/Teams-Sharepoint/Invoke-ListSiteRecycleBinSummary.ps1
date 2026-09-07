function Invoke-ListSiteRecycleBinSummary {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        Sharepoint.SiteRecycleBin.Read
    .DESCRIPTION
        Aggregate recycle bin sizes for a site (counts + bytes by stage). Never returns
        item titles, leaf names, or paths — storage-report privacy ceiling.
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $APIName = $Request.Params.CIPPEndpoint
    $TenantFilter = $Request.Query.TenantFilter ?? $Request.Query.tenantFilter ?? $Request.Body.TenantFilter ?? $Request.Body.tenantFilter
    $SiteUrl = $Request.Query.SiteUrl ?? $Request.Body.SiteUrl
    $MaxItems = [int]($Request.Query.MaxItems ?? $Request.Body.MaxItems ?? 5000)
    if ($MaxItems -lt 1) { $MaxItems = 5000 }
    if ($MaxItems -gt 20000) { $MaxItems = 20000 }

    try {
        if ([string]::IsNullOrWhiteSpace($TenantFilter)) { throw 'tenantFilter is required.' }
        if ([string]::IsNullOrWhiteSpace($SiteUrl)) { throw 'SiteUrl is required.' }

        $RestContext = Resolve-CIPPSharePointRestContext -TenantFilter $TenantFilter -SiteUrl $SiteUrl
        $Scope = $RestContext.Scope
        $JsonAccept = $RestContext.Headers
        $BaseUri = $RestContext.BaseUri

        $FirstCount = [int64]0
        $FirstBytes = [int64]0
        $SecondCount = [int64]0
        $SecondBytes = [int64]0
        $Seen = 0
        $Capped = $false
        $NextUri = "$BaseUri/site/RecycleBin?`$select=Id,Size,ItemState&`$top=500&`$orderby=DeletedDate desc"

        while ($NextUri) {
            $Page = New-GraphGetRequest -uri $NextUri -tenantid $TenantFilter -scope $Scope -extraHeaders $JsonAccept -UseCertificate -AsApp $true -noPagination $true -SkipValueExtraction
            $Items = @()
            $NextLink = $null
            if ($null -ne $Page.value) {
                $Items = @($Page.value)
                $NextLink = $Page.'@odata.nextLink'
            } elseif ($Page -is [System.Array]) {
                $Items = @($Page)
            } elseif ($Page.PSObject.Properties.Name -contains 'Id') {
                $Items = @($Page)
            }

            foreach ($Item in $Items) {
                if ($Seen -ge $MaxItems) {
                    $Capped = $true
                    break
                }
                $Seen++
                $Size = 0
                try { $Size = [int64][double]$Item.Size } catch { $Size = 0 }
                $State = 0
                try { $State = [int]$Item.ItemState } catch { $State = 0 }
                if ($State -eq 2) {
                    $SecondCount++
                    $SecondBytes += $Size
                } else {
                    $FirstCount++
                    $FirstBytes += $Size
                }
            }

            if ($Capped -or [string]::IsNullOrWhiteSpace($NextLink)) { break }
            $NextUri = $NextLink
        }

        $Body = [PSCustomObject]@{
            siteUrl          = $SiteUrl.TrimEnd('/')
            itemCount        = $FirstCount + $SecondCount
            totalBytes       = $FirstBytes + $SecondBytes
            firstStageCount  = $FirstCount
            firstStageBytes  = $FirstBytes
            secondStageCount = $SecondCount
            secondStageBytes = $SecondBytes
            capped           = $Capped
            scannedItems     = $Seen
        }
        $StatusCode = [HttpStatusCode]::OK
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        $Body = "Failed to summarize recycle bin for $($SiteUrl): $($ErrorMessage.NormalizedError)"
        Write-LogMessage -Headers $Request.Headers -API $APIName -tenant $TenantFilter -message $Body -sev Error -LogData $ErrorMessage
        $StatusCode = [HttpStatusCode]::BadRequest
    }

    return ([HttpResponseContext]@{
            StatusCode = $StatusCode
            Body       = @{ Results = $Body }
        })
}
