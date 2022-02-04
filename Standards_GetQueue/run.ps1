param($name)

$Tenants = Get-ChildItem "Cache_Standards\*.standards.json"

$object = foreach ($Tenant in $tenants) {
    $StandardsFile = Get-Content "$($tenant)" | ConvertFrom-Json
    $Standardsfile.Standards.psobject.properties.name | ForEach-Object { 
        $Standard = $_
        if ($standardsfile.Tenant -ne "AllTenants") {
            Write-Host "Not all tenants. Single object"
            [pscustomobject]@{ 
                Tenant   = $Standardsfile.Tenant
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