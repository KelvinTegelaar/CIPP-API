# Input bindings are passed in via param block.
param($Timer)

$Tenants = get-tenants -IncludeErrors | Where-Object { $_.customerId -ne $env:TenantId }
foreach ($Row in $Tenants) {
    Push-OutputBinding -Name Msg -Value $row
}