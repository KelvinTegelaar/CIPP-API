function Get-CIPPGeoIPLocation {
    [CmdletBinding()]
    param (
        [string]$IP
    )

    $CacheGeoIPTable = Get-CippTable -tablename 'cachegeoip'
    $30DaysAgo = (Get-Date).AddDays(-30).ToString('yyyy-MM-ddTHH:mm:ssZ')
    $Filter = "PartitionKey eq 'IP' and RowKey eq '$IP' and Timestamp ge datetime'$30DaysAgo'"
    $GeoIP = Get-CippAzDataTableEntity @CacheGeoIPTable -Filter $Filter
    if ($GeoIP) {
        return ($GeoIP.Data | ConvertFrom-Json)
    }
    $location = Invoke-RestMethod "https://geoipdb.azurewebsites.net/api/GetIPInfo?IP=$IP"
    if ($location.status -eq 'FAIL') { throw "Could not get location for $IP" }
    $CacheGeo = @{
        PartitionKey = 'IP'
        RowKey       = $IP
        Data         = [string]($location | ConvertTo-Json -Compress)
    }
    Add-AzDataTableEntity @CacheGeoIPTable -Entity $CacheGeo -Force
    return $location
}
