param($name)

$Skiplist = (Get-Content ExcludedTenants -ErrorAction SilentlyContinue | ConvertFrom-Csv -Delimiter "|" -Header "name", "date", "user").name
$Tenants = Get-Content ".\tenants.cache.json" | ConvertFrom-Json | Where-Object { $Skiplist -notcontains $_.defaultDomainName }

$object = foreach ($Tenant in $Tenants) {
    # Get Domains to Lookup
    $Domains = New-GraphGetRequest -uri "https://graph.microsoft.com/v1.0/domains" -tenantid $Tenant.defaultDomainName | Where-Object { $_.id -notlike '*.onmicrosoft.com' }
    foreach ($d in $domains) {
        [PSCustomObject]@{
            Tenant             = $Tenant.defaultDomainName
            Domain             = $d.id
            AuthenticationType = $d.authenticationType
            IsAdminManaged     = $d.isAdminManaged
            IsDefault          = $d.isDefault
            IsInitial          = $d.isInitial
            IsRoot             = $d.isRoot
            IsVerified         = $d.isVerified
            SupportedServices  = $d.supportedServices
        }
    }
    
}

$object