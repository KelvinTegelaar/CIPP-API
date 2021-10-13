param($name)

$Tenants = get-childitem "*.standards.json"

$object = foreach ($Tenant in $tenants) {
    $StandardsFile = get-content "$($tenant)" | convertfrom-json
    $Standardsfile.Standards.psobject.properties.name | foreach-object { 
        [pscustomobject]@{ 
            Tenant = $Standardsfile.Tenant
         Standard = $_ }
    }

}
$object