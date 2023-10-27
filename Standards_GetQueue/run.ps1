param($name)

Write-Host 'QUEUEQUE'
$Table = Get-CippTable -tablename 'standards'
$SkipList = Get-Tenants -SkipList
$Tenants = (Get-CIPPAzDataTableEntity @Table -Filter $Filter).JSON | ConvertFrom-Json

$object = foreach ($Tenant in $Tenants) {
    $Tenant.standards.psobject.properties.name | ForEach-Object {
        $Standard = $_
        if ($Tenant.Tenant -ne 'AllTenants' -and $SkipList.defaultDomainName -notcontains $Tenant.Tenant) {
            Write-Host 'Not all tenants. Single object'
            [pscustomobject]@{
                Tenant   = $tenant.Tenant
                Standard = $Standard
            }
        } elseif ($Tenant.Tenant -eq 'AllTenants') {
            Get-Tenants | ForEach-Object {
                $Tenant = $_
                $TenantStandard = $Tenants | Where-Object { $_.Tenant -eq $Tenant.defaultDomainName }
                if ($TenantStandard.OverrideAllTenants -ne $true) {
                    [pscustomobject]@{
                        Tenant   = $_.defaultDomainName
                        Standard = $Standard
                    }
                }
            }
        }
    }
}
$object