function Get-CIPPOSLifecycle {
    <#
    .SYNOPSIS
        Returns the release list for an operating system from endoflife.date, cached for a day.
    .DESCRIPTION
        Product is an endoflife.date product name (ios, macos, android, windows). The list is kept in
        the OSLifecycle table so a baseline run costs one request per product per day for the whole
        CIPP instance. When endoflife.date cannot be reached the last stored copy is returned, whatever
        its age; with no stored copy the error is thrown.
    .FUNCTIONALITY
        Internal
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateSet('ios', 'macos', 'android', 'windows')]
        [string]$Product,
        [switch]$SkipCache
    )

    $Table = Get-CIPPTable -tablename 'OSLifecycle'
    $Cached = Get-CIPPAzDataTableEntity @Table -Filter "PartitionKey eq 'endoflife' and RowKey eq '$Product'"
    $CachedReleases = if ($Cached.JSON -and (Test-Json $Cached.JSON)) { @(ConvertFrom-Json -InputObject $Cached.JSON) }
    if (-not $SkipCache -and $CachedReleases -and $Cached.Timestamp -gt (Get-Date).ToUniversalTime().AddHours(-24)) {
        return $CachedReleases
    }

    try {
        $Response = Invoke-RestMethod -Uri "https://endoflife.date/api/v1/products/$Product/" -Method GET -TimeoutSec 30
        # Only the fields that are used, so the Windows list stays inside one table property.
        $Releases = @($Response.result.releases | Where-Object { $_.name } | ForEach-Object {
                [PSCustomObject]@{
                    name          = "$($_.name)"
                    releaseDate   = $_.releaseDate
                    isLts         = [bool]$_.isLts
                    isMaintained  = [bool]$_.isMaintained
                    eolFrom       = $_.eolFrom
                    latestVersion = $_.latest.name
                    latestDate    = $_.latest.date
                }
            })
        if ($Releases.Count -eq 0) { throw 'the response contained no releases' }
    } catch {
        if ($CachedReleases) {
            Write-Information "OS lifecycle: endoflife.date lookup for $Product failed, using the stored copy: $($_.Exception.Message)"
            return $CachedReleases
        }
        throw "Could not get the $Product release list from endoflife.date: $($_.Exception.Message)"
    }

    Add-CIPPAzDataTableEntity @Table -Force -Entity @{
        PartitionKey = 'endoflife'
        RowKey       = $Product
        JSON         = [string](ConvertTo-Json -Compress -Depth 10 -InputObject $Releases)
    }
    $Releases
}
