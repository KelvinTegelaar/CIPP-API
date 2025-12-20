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

    if ($Name) {
        $Conditions.Add("RowKey eq '$($Name)' or OriginalEntityId eq '$($Name)'")
    }

    if ($NameOnly.IsPresent) {
        $Table.Property = @('RowKey')
    }

    $Filter = $Conditions -join ' and '
    $Table.Filter = $Filter
    $Info = Get-CIPPAzDataTableEntity @Table

    if ($NameOnly.IsPresent) {
        $Info = $Info | Where-Object { $_.RowKey -notmatch '-part[0-9]+$' }
        if ($TenantFilter) {
            $Info = $Info | Where-Object { $_.RowKey -match "^$($TenantFilter)_" }
        }
    } else {
        if ($TenantFilter -and $TenantFilter -ne 'AllTenants') {
            $Info = $Info | Where-Object { $_.TenantFilter -eq $TenantFilter }
        }
    }
    return $Info
}
