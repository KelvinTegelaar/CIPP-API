# Input bindings are passed in via param block.
param($Timer)

#Switched to run for every tenant always, to make sure app permissions get applied succesfully.
$Tenants = get-tenants
foreach ($Row in $Tenants ) {
    Write-Host "Processing tenants"
    Push-OutputBinding -Name Msg -Value $row.customerId
}
