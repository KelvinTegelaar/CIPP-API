function Get-BreachInfo {
    [CmdletBinding()]
    param(
        [Parameter()]
        $TenantFilter
    )
    $Data = New-GraphGetRequest -uri 'https://graph.microsoft.com/beta/domains' -tenantid $TenantFilter | ForEach-Object {
        Invoke-RestMethod -Uri "https://geoipdb.azurewebsites.net/api/Breach?func=domain&domain=$($_.id)"
    }
    return $Data
}
