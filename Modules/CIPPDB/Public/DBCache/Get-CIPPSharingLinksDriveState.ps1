function Get-CIPPSharingLinksDriveState {
    <#
    .SYNOPSIS
        Returns per-drive delta-scan state: one drive's row, or every drive's when -DriveId is omitted.
    .DESCRIPTION
        Drive state lives in the CippSharingLinksState table under RowKey 'delta-{driveId}': the
        deltaLink captured when the drive last completed (used for incremental scans), which scan
        last saw the drive (used to prune drives that no longer exist), and when it last had a
        FULL scan (used to bound incremental drift). Written by the site activity; read here by
        the activity, the fan-out parent and the finaliser.
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
        $RowKey = "delta-$(ConvertTo-CIPPSharingLinksKeySegment -Value $DriveId)"
        Get-CIPPAzDataTableEntity @Table -Filter "PartitionKey eq '$SafeTenant' and RowKey eq '$RowKey'"
    } else {
        Get-CIPPAzDataTableEntity @Table -Filter "PartitionKey eq '$SafeTenant' and RowKey ge 'delta-' and RowKey lt 'delta.'"
    }
}
