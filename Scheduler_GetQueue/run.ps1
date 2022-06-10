param($name)

$Table = Get-CIPPTable -TableName SchedulerConfig
$Tenants = Get-AzTableRow -Table $table

$object = foreach ($Tenant in $tenants) {
    if ($Tenant.Tenant -ne "AllTenants") {
        [pscustomobject]@{ 
            Tenant   = $Tenant.Tenant
            Tag      = "SingleTenant"
            TenantID = $Tenant.tenantId
            Type     = $Tenant.Type
        }
    }
    else {
        Write-Host "All tenants, doing them all"
        get-tenants | ForEach-Object {
            [pscustomobject]@{ 
                Tenant   = $_.defaultDomainName
                Tag      = "AllTenants"
                TenantID = $_.customerId
                Type     = $Tenant.Type
            }
        }
    }
}


$object