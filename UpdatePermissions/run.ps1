# Input bindings are passed in via param block.
param($Timer)

$Tenants = get-tenants -IncludeAll
foreach ($Row in $Tenants) {
    Push-OutputBinding -Name Msg -Value $row
}