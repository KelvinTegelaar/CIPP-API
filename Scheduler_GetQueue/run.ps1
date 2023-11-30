param($name)

$Table = Get-CIPPTable -TableName SchedulerConfig
$Tenants = Get-CIPPAzDataTableEntity @Table

$object = foreach ($Tenant in $Tenants) {
    if ($Tenant.tenant -ne 'AllTenants') {
        [pscustomobject]@{ 
            Tenant   = $Tenant.tenant
            Tag      = 'SingleTenant'
            TenantID = $Tenant.tenantid
            Type     = $Tenant.type
        }
    }
    else {
        Write-Host 'All tenants, doing them all'
        $TenantList = Get-Tenants
        foreach ($t in $TenantList) {
            [pscustomobject]@{ 
                Tenant   = $t.defaultDomainName
                Tag      = 'AllTenants'
                TenantID = $t.customerId
                Type     = $Tenant.type
            }
        }
    }
}

$object