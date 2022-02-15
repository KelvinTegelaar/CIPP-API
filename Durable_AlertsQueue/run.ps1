param($name)
Write-Host "0000000000000000000000000000000000"
Write-Host $name
$Tenants = if ($name -eq "AllTenants") {
    Get-Tenants
}
else {
    Get-tenants | Where-Object -Property defaultDomainName -EQ $name
}

$Tenants
