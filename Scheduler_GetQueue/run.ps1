param($name)

$Tenants = Get-ChildItem "Cache_Scheduler\*.json"

$object = foreach ($Tenant in $tenants) {
    $TypeFile = Get-Content "$($tenant)" | ConvertFrom-Json
    if ($Typefile.Tenant -ne "AllTenants") {
        [pscustomobject]@{ 
            Tenant   = $Typefile.Tenant
            Tag      = "SingleTenant"
            TenantID = $TypeFile.tenantId
            Type     = $Typefile.Type
        }
    }
    else {
        Write-Host "All tenants, doing them all"
        get-tenants | ForEach-Object {
            [pscustomobject]@{ 
                Tenant   = $_.defaultDomainName
                Tag      = "AllTenants"
                TenantID = $_.customerId
                Type     = $Typefile.Type
            }
        }
    }
}


$object