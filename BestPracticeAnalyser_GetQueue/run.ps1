param($name)

$Tenants = Get-Content ".\tenants.cache.json" | ConvertFrom-Json

$object = foreach ($Tenant in $Tenants) {
    $Tenant.defaultDomainName
}

$object