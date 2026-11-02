function Remove-CIPPSharingLinksRowsByPrefix {
    <#
    .SYNOPSIS
        Deletes CippSharingLinks rows whose RowKey starts with the given prefix.
    .DESCRIPTION
        -ExceptScanId keeps rows stamped with that scan's id (used after a full drive scan to
        drop only the rows the scan did not rewrite). The '~' upper bound (0x7E) sorts after every
        character a sanitised id can contain, so [prefix, prefix~) covers exactly the keys that
        start with prefix. Returns the number of rows deleted.
    .FUNCTIONALITY
        Internal
    #>
    param(
        [Parameter(Mandatory = $true)][string]$TenantFilter,
        [AllowEmptyString()][string]$Prefix = '',
        [string]$ExceptScanId
    )
    $Table = Get-CippTable -tablename 'CippSharingLinks'
    $ToDelete = foreach ($Row in (Get-CIPPSharingLinksRowKeysByPrefix -TenantFilter $TenantFilter -Prefix $Prefix)) {
        if (-not $Row) { continue }
        if ($ExceptScanId -and [string]$Row.ScanId -eq $ExceptScanId) { continue }
        $Row
    }
    if (@($ToDelete).Count -gt 0) {
        $null = Remove-CIPPAzDataTableEntity @Table -Entity @($ToDelete) -Force
    }
    return @($ToDelete).Count
}
