function Get-BreachInfo {
    [CmdletBinding()]
    param(
        [Parameter()]
        $TenantFilter,
        [Parameter()]$Domain

    )
    if ($TenantFilter) {
        $Data = New-GraphGetRequest -uri 'https://graph.microsoft.com/beta/domains' -tenantid $TenantFilter | ForEach-Object {
            Invoke-RestMethod -Uri "https://geoipdb.azurewebsites.net/api/Breach?func=domain&domain=$($_.id)"
        }
        return $Data
    } else {
       $data = Invoke-RestMethod -Uri "https://geoipdb.azurewebsites.net/api/Breach?func=domain&domain=$($domain)&format=breachlist"
       return $Data
    }

}
