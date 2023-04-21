param($name)

$Table = Get-CippTable -tablename 'apps'

$Object = (Get-AzDataTableEntity @Table).RowKey
$object