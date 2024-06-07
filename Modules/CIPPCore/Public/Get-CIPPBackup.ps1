function Get-CIPPBackup {
    [CmdletBinding()]
    param (
        [string]$Type,
        [string]$TenantFilter
    )
    $Table = Get-CippTable -tablename "$($Type)Backup"
    if ($TenantFilter) {
        $Filter = "PartitionKey eq '$($Type)Backup' and TenantFilter eq '$($TenantFilter)'"
        $Table.Filter = $Filter
    }
    $Info = Get-CIPPAzDataTableEntity @Table
    return $info
}
