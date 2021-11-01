param($name)

$Skiplist = (Get-Content ExcludedTenants -ErrorAction SilentlyContinue | ConvertFrom-Csv -Delimiter "|" -Header "name", "date", "user").name
$Tenants = Get-Content ".\tenants.cache.json" | ConvertFrom-Json | Where-Object {$Skiplist -notcontains $_.defaultDomainName} | Select -First 10

$object = foreach ($Tenant in $Tenants) {
    $Tenant.defaultDomainName
}

$object