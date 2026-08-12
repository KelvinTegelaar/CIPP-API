function Remove-CIPPSharingLinksRowsByPrefix {
    <#
    .SYNOPSIS
        Deletes CippReportingDB rows whose RowKey starts with the given prefix.
    .DESCRIPTION
        -ExceptRunId keeps rows stamped with that run's id (used after a full drive scan to
        drop only the rows the scan did not rewrite). -ExceptRowKeys keeps exact keys (the
        {Type}-Count row). The '~' upper bound (0x7E) sorts after every character a sanitised
        id can contain, so [prefix, prefix~) covers exactly the keys that start with prefix.
        Returns the number of rows deleted.
    .FUNCTIONALITY
        Internal
    #>
    param(
        [Parameter(Mandatory = $true)][string]$TenantFilter,
        [Parameter(Mandatory = $true)][string]$Prefix,
        [string]$ExceptRunId,
        [string[]]$ExceptRowKeys = @()
    )
    $Table = Get-CippTable -tablename 'CippReportingDB'
    $SafeTenant = ConvertTo-CIPPODataFilterValue -Value $TenantFilter -Type String
    $SafePrefix = ConvertTo-CIPPODataFilterValue -Value $Prefix -Type String
    $Filter = "PartitionKey eq '{0}' and RowKey ge '{1}' and RowKey lt '{1}~'" -f $SafeTenant, $SafePrefix
    $Properties = @('PartitionKey', 'RowKey', 'ETag')
    if ($ExceptRunId) { $Properties += 'RunId' }
    $Rows = Get-CIPPAzDataTableEntity @Table -Filter $Filter -Property $Properties
    $ToDelete = foreach ($Row in @($Rows)) {
        if (-not $Row) { continue }
        if ($ExceptRowKeys -contains $Row.RowKey) { continue }
        if ($ExceptRunId -and [string]$Row.RunId -eq $ExceptRunId) { continue }
        $Row
    }
    if (@($ToDelete).Count -gt 0) {
        $null = Remove-CIPPAzDataTableEntity @Table -Entity @($ToDelete) -Force
    }
    return @($ToDelete).Count
}
