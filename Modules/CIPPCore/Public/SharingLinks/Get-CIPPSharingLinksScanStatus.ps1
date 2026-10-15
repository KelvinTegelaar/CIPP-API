function Get-CIPPSharingLinksScanStatus {
    <#
    .SYNOPSIS
        Whether a tenant's sharing-links scan is still running, and the queue tracking it.
    .DESCRIPTION
        A scan is in progress from its 'scan' state row until it writes its 'final' marker. One that
        has not finalised within 24 hours is treated as abandoned, so a lost run cannot block new scans.
        -Libraries adds each library's progress: the ones being scanned with items seen of SharePoint's
        item count, and the 200 most recently finished.
    .FUNCTIONALITY
        Internal
    #>
    param(
        [Parameter(Mandatory = $true)][string]$TenantFilter,
        [switch]$Libraries
    )

    $TenantFilter = @(Get-Tenants -TenantFilter $TenantFilter -IncludeErrors)[0].defaultDomainName ?? $TenantFilter
    $SafeTenant = ConvertTo-CIPPODataFilterValue -Value $TenantFilter -Type String
    $StateTable = Get-CippTable -tablename 'CippSharingLinksState'
    $Scan = Get-CIPPAzDataTableEntity @StateTable -Filter "PartitionKey eq '$SafeTenant' and RowKey eq 'scan'"
    $Final = Get-CIPPAzDataTableEntity @StateTable -Filter "PartitionKey eq '$SafeTenant' and RowKey eq 'final'"
    $Finalised = [bool]$Final -and [string]$Final.ScanId -eq [string]$Scan.ScanId
    $Started = $(try { [DateTimeOffset]::Parse([string]$Scan.StartedUtc) } catch { [DateTimeOffset]::MinValue })
    $Status = [ordered]@{
        inProgress = [bool]$Scan -and -not $Finalised -and $Started -gt [DateTimeOffset]::UtcNow.AddHours(-24)
        queueId    = [string]$Scan.QueueId
        startedUtc = [string]$Scan.StartedUtc
        phase      = [string]$Scan.Phase
    }
    if (-not $Libraries -or -not $Scan) { return [PSCustomObject]$Status }

    $ScanId = [string]$Scan.ScanId
    $Range = "PartitionKey eq '$SafeTenant' and RowKey ge '{0}' and RowKey lt '{0}~'"
    $Done = @{}
    foreach ($Row in @(Get-CIPPAzDataTableEntity @StateTable -Filter ($Range -f 'ddone-') -Property @('RowKey', 'ScanId', 'Timestamp'))) {
        if ([string]$Row.ScanId -eq $ScanId) { $Done[([string]$Row.RowKey).Substring('ddone-'.Length)] = $Row.Timestamp }
    }
    $Scanning = @{}
    foreach ($Row in @(Get-CIPPAzDataTableEntity @StateTable -Filter ($Range -f 'chk-') -Property @('RowKey', 'ScanId', 'StateJson'))) {
        if ([string]$Row.ScanId -eq $ScanId -and $Row.StateJson) { $Scanning[([string]$Row.RowKey).Substring('chk-'.Length)] = ConvertFrom-Json -InputObject ([string]$Row.StateJson) }
    }
    $All = foreach ($Site in @(Get-CIPPAzDataTableEntity @StateTable -Filter ($Range -f 'drives-') -Property @('RowKey', 'ScanId', 'SiteName', 'SiteUrl', 'DrivesJson'))) {
        if ([string]$Site.ScanId -ne $ScanId -or -not $Site.DrivesJson) { continue }
        $SiteKey = ([string]$Site.RowKey).Substring('drives-'.Length)
        foreach ($Drive in @(ConvertFrom-Json -InputObject ([string]$Site.DrivesJson))) {
            $Key = "$SiteKey~$([string]$Drive.id -replace '[/\\#?]', '_' -replace '[\u0000-\u001F\u007F-\u009F]', '')"
            $Progress = $Scanning[$Key]
            [PSCustomObject]@{
                site      = [string]($Site.SiteName ? $Site.SiteName : $Site.SiteUrl)
                library   = [string]$Drive.name
                itemCount = [int64]($Drive.itemCount ?? -1)
                itemsSeen = [int64]($Progress.ItemsSeen ?? 0)
                mode      = [string]$Progress.CurrentMode
                status    = if ($Done.ContainsKey($Key)) { 'done' } elseif ($Progress) { 'scanning' } else { 'queued' }
                doneAt    = $Done[$Key]
            }
        }
    }
    $All = @($All)
    $Finished = @($All.Where({ $_.status -eq 'done' }) | Sort-Object -Property doneAt -Descending)
    $Status.librariesTotal = $All.Count
    $Status.librariesDone = $Finished.Count
    $Status.libraries = @(@(
            $All.Where({ $_.status -eq 'scanning' })
            if ($Finished.Count -gt 0) { $Finished[0..([Math]::Min(199, $Finished.Count - 1))] }
        ) | Select-Object -Property site, library, itemCount, itemsSeen, mode, status)
    [PSCustomObject]$Status
}
