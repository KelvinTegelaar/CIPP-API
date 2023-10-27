param($name)

$Table = Get-CippTable -tablename 'apps'

$Object = (Get-CIPPAzDataTableEntity @Table).RowKey
$object