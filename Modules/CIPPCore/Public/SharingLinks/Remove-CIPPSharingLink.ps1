function Remove-CIPPSharingLink {
    <#
    .SYNOPSIS
        Removes a revoked sharing link's row from CippSharingLinks and lowers its drive's recorded row count.
    .DESCRIPTION
        The scan rescans a drive in full when it holds fewer rows than its recorded count, so a removal
        outside the scan lowers the count with it.
    .FUNCTIONALITY
        Internal
    #>
    param(
        [Parameter(Mandatory = $true)][string]$TenantFilter,
        [Parameter(Mandatory = $true)][string]$Id
    )

    $TenantFilter = @(Get-Tenants -TenantFilter $TenantFilter -IncludeErrors)[0].defaultDomainName ?? $TenantFilter
    $SafeTenant = ConvertTo-CIPPODataFilterValue -Value $TenantFilter -Type String
    $Table = Get-CippTable -tablename 'CippSharingLinks'
    $RowKey = ConvertTo-CIPPODataFilterValue -Value ([string]$Id -replace '[/\\#?]', '_' -replace '[\u0000-\u001F\u007F-\u009F]', '') -Type String
    $Row = Get-CIPPAzDataTableEntity @Table -Filter "PartitionKey eq '$SafeTenant' and RowKey eq '$RowKey'" -Property @('PartitionKey', 'RowKey', 'ETag', 'driveId')
    if (-not $Row) { return }
    Remove-CIPPAzDataTableEntity @Table -Entity $Row -Force

    $StateTable = Get-CippTable -tablename 'CippSharingLinksState'
    $DriveKey = ConvertTo-CIPPODataFilterValue -Value "delta-$([string]$Row.driveId -replace '[/\\#?]', '_' -replace '[\u0000-\u001F\u007F-\u009F]', '')" -Type String
    $DriveState = Get-CIPPAzDataTableEntity @StateTable -Filter "PartitionKey eq '$SafeTenant' and RowKey eq '$DriveKey'"
    if ([int]$DriveState.RowCount -gt 0) {
        $DriveState.RowCount = [int]$DriveState.RowCount - 1
        Add-CIPPAzDataTableEntity @StateTable -Entity $DriveState -Force
    }
}
