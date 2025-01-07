function Get-CIPPBackup {
    [CmdletBinding()]
    param (
        [string]$Type = 'CIPP',
        [string]$TenantFilter,
        [string]$Name,
        [switch]$NameOnly
    )
    Write-Host "Getting backup for $Type with TenantFilter $TenantFilter"
    $Table = Get-CippTable -tablename "$($Type)Backup"

    $Conditions = [System.Collections.Generic.List[string]]::new()
    $Conditions.Add("PartitionKey eq '$($Type)Backup'")

    if ($TenantFilter) {
        $Conditions.Add("TenantFilter eq '$($TenantFilter)'")
    }
    if ($Name) {
        $Conditions.Add("RowKey eq '$($Name)' or OriginalEntityId eq '$($Name)'")
    }

    if ($NameOnly.IsPresent) {
        $Table.Property = @('PartitionKey', 'RowKey', 'Timestamp', 'OriginalEntityId')
    }

    $Filter = $Conditions -join ' and '
    $Table.Filter = $Filter

    $Info = Get-CIPPAzDataTableEntity @Table
    return $info
}
