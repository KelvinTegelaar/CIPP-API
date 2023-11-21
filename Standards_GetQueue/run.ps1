param($name)

Write-Host 'QUEUEQUE'
$Table = Get-CippTable -tablename 'standards'
$SkipList = Get-Tenants -SkipList
$Tenants = (Get-CIPPAzDataTableEntity @Table -Filter $Filter).JSON | ConvertFrom-Json

$object = foreach ($Tenant in $Tenants) {
    $Tenant.standards.psobject.properties.name | ForEach-Object {
        $Standard = $_
        Write-Host "Standard is $Standard"
        if ($Tenant.Tenant -ne 'AllTenants' -and $SkipList.defaultDomainName -notcontains $Tenant.Tenant) {
            Write-Host 'Not all tenants. Single object'
            if ($Standard -ne "OverrideAllTenants") {
                [pscustomobject]@{
                    Tenant   = $tenant.Tenant
                    Standard = $Standard
                }
            }
        }
        elseif ($Tenant.Tenant -eq 'AllTenants') {
            Get-Tenants | ForEach-Object {
                $TenantForStandard = $_
                $TenantStandard = $Tenants | Where-Object { $_.Tenant -eq $TenantForStandard.defaultDomainName }
                Write-Host "Working on all Tenants. Current Tenant is $($Tenant.defaultDomainName) and standard is $Standard"
                if ($TenantStandard.standards.OverrideAllTenants -ne $true) {
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