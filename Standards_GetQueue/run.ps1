param($name)

$OldStandards = Get-ChildItem "*.standards.json" | ForEach-Object { 
    Copy-Item -Path $_.FullName -Destination "Cache_Standards\$($_.name)" -Force ; 
    Remove-Item $_.fullname -Force }
$Tenants = Get-ChildItem "Cache_Standards\*.standards.json"

$object = foreach ($Tenant in $tenants) {
    $StandardsFile = Get-Content "$($tenant)" | ConvertFrom-Json
    $Standardsfile.Standards.psobject.properties.name | ForEach-Object { 
        [pscustomobject]@{ 
            Tenant   = $Standardsfile.Tenant
            Standard = $_ 
        }
    }

}
$object