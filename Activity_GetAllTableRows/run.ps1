param($name)

$Table = Get-CippTable -tablename $name
$Rows = Get-AzDataTableEntity @Table

Write-Output $Rows