function Get-CIPPGeoIPLocation {
    [CmdletBinding()]
    param (
        [string]$IP
    )

    $CacheGeoIPTable = Get-CippTable -tablename 'cachegeoip'
    $1DayAgo = (Get-Date).AddDays(-1).ToString('yyyy-MM-ddTHH:mm:ssZ')
    $Filter = "PartitionKey eq 'IP' and RowKey eq '$IP' and Timestamp ge datetime'$1DayAgo'"
    $GeoIP = Get-CippAzDataTableEntity @CacheGeoIPTable -Filter $Filter
    if ($GeoIP -and $GeoIP.Data) {
        return ($GeoIP.Data | ConvertFrom-Json)
    }
    $location = Invoke-CIPPRestMethod -Uri "https://geoipdb.azurewebsites.net/api/GetIPInfo?IP=$IP"
    if ($location.status -eq 'FAIL') {
        Write-logMessage -API GeoIPLocation -message "Failed to get location for $IP. API returned status 'FAIL' with message: $($location.message)" -sev Warning
        throw "Could not get location for $IP"
    }
    $CacheGeo = @{
        PartitionKey = 'IP'
        RowKey       = $IP
        Data         = [string]($location | ConvertTo-Json -Compress)
    }
    Add-AzDataTableEntity @CacheGeoIPTable -Entity $CacheGeo -Force
    return $location
}
