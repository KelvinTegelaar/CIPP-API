function Get-CIPPGeoIPLocation {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [string]$IP
    )

    $CacheGeoIPTable = Get-CippTable -tablename 'cachegeoip'
    $30DaysAgo = (Get-Date).AddDays(-30).ToString('yyyy-MM-ddTHH:mm:ssZ')
    $Filter = "PartitionKey eq 'IP' and RowKey eq '$IP' and Timestamp ge datetime'$30DaysAgo'"
    $ParsedIPAddress = $null
    $IsIPv6 = $false
    $CountryFallbackUsed = $false

    try {
        $ParsedIPAddress = [System.Net.IPAddress]::Parse($IP)
        $IsIPv6 = $ParsedIPAddress.AddressFamily -eq [System.Net.Sockets.AddressFamily]::InterNetworkV6
    } catch {
        $ParsedIPAddress = $null
    }

    $GeoIP = Get-CippAzDataTableEntity @CacheGeoIPTable -Filter $Filter
    if ($GeoIP -and $GeoIP.Data) {
        $CachedLocation = $GeoIP.Data | ConvertFrom-Json -ErrorAction SilentlyContinue
        $CachedCountry = $CachedLocation.countryCode ?? $CachedLocation.CountryOrRegion ?? $CachedLocation.country
        if (-not ($IsIPv6 -and ([string]::IsNullOrWhiteSpace($CachedCountry) -or $CachedCountry -eq 'Unknown'))) {
            return $CachedLocation
        }
    }

    $EncodedIP = [System.Uri]::EscapeDataString($IP)
    $Location = $null
    try {
        $Location = Invoke-CIPPRestMethod -Uri "https://geoipdb.azurewebsites.net/api/GetIPInfo?IP=$EncodedIP"
    } catch {
        Write-Information "Primary GeoIP lookup failed for ${IP}: $($_.Exception.Message)"
        $Location = $null
    }

    $CountryCode = $Location.countryCode ?? $Location.CountryOrRegion ?? $Location.country
    $City = $Location.city ?? $Location.City
    $Proxy = if ($null -ne $Location.proxy) { $Location.proxy } elseif ($null -ne $Location.Proxy) { $Location.Proxy } else { $null }
    $Hosting = if ($null -ne $Location.hosting) { $Location.hosting } elseif ($null -ne $Location.Hosting) { $Location.Hosting } else { $null }
    $ASName = $Location.asname ?? $Location.ASName

    if ($IsIPv6 -and ($null -eq $Location -or $Location.status -eq 'FAIL' -or [string]::IsNullOrWhiteSpace($CountryCode) -or $CountryCode -eq 'Unknown')) {
        try {
            $CountryFallback = Invoke-CIPPRestMethod -Uri "https://api.country.is/$EncodedIP"
            if (-not [string]::IsNullOrWhiteSpace($CountryFallback.country)) {
                $CountryCode = $CountryFallback.country
                $CountryFallbackUsed = $true
                Write-Information "GeoIP fallback resolved IPv6 country for $IP via api.country.is"
            }
        } catch {
            $CountryFallbackUsed = $false
        }
    }

    if (($null -eq $Location -or $Location.status -eq 'FAIL') -and -not $CountryFallbackUsed) {
        throw "Could not get location for $IP"
    }

    $LocationDataValues = @(
        $CountryCode,
        $City,
        $(if ($null -ne $Proxy) { [string]$Proxy } else { $null }),
        $(if ($null -ne $Hosting) { [string]$Hosting } else { $null }),
        $ASName
    )
    $HasLocationData = $LocationDataValues | Where-Object {
        -not [string]::IsNullOrWhiteSpace($_) -and $_ -ne 'Unknown'
    }
    if (@($HasLocationData).Count -eq 0) {
        throw "Could not get location for $IP"
    }

    $NormalizedLocation = [PSCustomObject]@{
        ip              = $IP
        countryCode     = $CountryCode
        city            = $City
        proxy           = $Proxy
        hosting         = $Hosting
        asname          = $ASName
        CountryOrRegion = $CountryCode
        source          = if ($CountryFallbackUsed) {
            if ($null -ne $Location -and $Location.status -ne 'FAIL') { 'geoipdb+country.is' } else { 'country.is' }
        } else {
            'geoipdb'
        }
    }

    $CacheGeo = @{
        PartitionKey = 'IP'
        RowKey       = $IP
        Data         = [string]($NormalizedLocation | ConvertTo-Json -Compress -Depth 10)
    }
    Add-AzDataTableEntity @CacheGeoIPTable -Entity $CacheGeo -Force
    return $NormalizedLocation
}
