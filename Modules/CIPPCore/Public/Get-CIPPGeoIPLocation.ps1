function Get-CIPPGeoIPLocation {
    [CmdletBinding()]
    param (
        [string]$IP
    )
    $location = Invoke-RestMethod "https://geoipdb.azurewebsites.net/api/GetIPInfo?IP=$IP"
    if ($location.status -eq 'FAIL') { throw "Could not get location for $IP" }
    return $location
}
