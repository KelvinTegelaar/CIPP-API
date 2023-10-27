param($name)

$Table = Get-CippTable -tablename $name
$Rows = Get-CIPPAzDataTableEntity @Table

Write-Output $Rows