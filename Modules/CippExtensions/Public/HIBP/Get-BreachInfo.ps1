function Get-BreachInfo {
    [CmdletBinding()]
    param(
        [Parameter()]
        $TenantFilter
    )
    $Data = New-GraphGetRequest -uri 'https://graph.microsoft.com/beta/domains' -tenantid $TenantFilter | ForEach-Object {
        $uri = 'https://geoipdb.azurewebsites.net/api/Breach?func=domain&domain=limenetworks.nl'
        Invoke-RestMethod -Uri $uri
    }
    return $Data
}
