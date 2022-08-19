param($name)

$Table = Get-CippTable -tablename 'apps'

$Object = (Get-AzDataTableRow @Table).RowKey
$object