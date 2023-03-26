param($name)

Write-Host 'QUEUEQUE'
$Table = Get-CippTable -tablename 'standards'
$tenants = (Get-AzDataTableEntity @Table -Filter $Filter).JSON | ConvertFrom-Json

$object = foreach ($Tenant in $tenants) {
    $tenant.standards.psobject.properties.name | ForEach-Object { 
        $Standard = $_
        if ($tenant.Tenant -ne 'AllTenants') {
            Write-Host 'Not all tenants. Single object'
            [pscustomobject]@{ 
                Tenant   = $tenant.Tenant
                Standard = $Standard
            }
        }
        else {
            get-tenants | ForEach-Object {
                [pscustomobject]@{ 
                    Tenant   = $_.defaultDomainName
                    Standard = $Standard 
                }
            }
        }
    }

}
$object