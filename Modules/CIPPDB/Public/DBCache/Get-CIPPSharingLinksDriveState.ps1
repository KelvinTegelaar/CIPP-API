function Get-CIPPSharingLinksDriveState {
    <#
    .SYNOPSIS
        Returns per-drive delta-scan state: one drive's row, or every drive's when -DriveId is omitted.
    .DESCRIPTION
        Drive state lives in the CippSharingLinksState table under RowKey 'delta-{driveId}': the
        deltaLink captured when the drive last completed (used for incremental scans), which scan
        last saw the drive (used to prune drives that no longer exist), and how many rows it held
        (a drive holding fewer is rescanned in full). Written by the site activity; read here by
        the activity and the finaliser.
    .FUNCTIONALITY
        Internal
    #>
    param(
        [Parameter(Mandatory = $true)][string]$TenantFilter,
        [string]$DriveId
    )
    $Table = Get-CippTable -tablename 'CippSharingLinksState'
    $SafeTenant = ConvertTo-CIPPODataFilterValue -Value $TenantFilter -Type String
    if ($DriveId) {
        $RowKey = "delta-$([string]$DriveId -replace '[/\\#?]', '_' -replace '[\u0000-\u001F\u007F-\u009F]', '')"
        Get-CIPPAzDataTableEntity @Table -Filter "PartitionKey eq '$SafeTenant' and RowKey eq '$RowKey'"
    } else {
        Get-CIPPAzDataTableEntity @Table -Filter "PartitionKey eq '$SafeTenant' and RowKey ge 'delta-' and RowKey lt 'delta.'"
    }
}
