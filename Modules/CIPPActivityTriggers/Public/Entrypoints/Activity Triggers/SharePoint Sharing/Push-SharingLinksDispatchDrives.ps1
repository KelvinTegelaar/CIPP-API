function Push-SharingLinksDispatchDrives {
    <#
    .SYNOPSIS
        Post-execution for a tenant's sharing-links site run and each drive run: queues the scan's unfinished drives

    .DESCRIPTION
        Every drive of the scan without a completion marker is queued as one run of at most three at
        a time, whose post-execution is this function again. A drive task killed at the platform limit
        or throttled out mid-scan resumes from its checkpoint in the next round, for as long as it
        keeps saving pages. A drive that saved none since the last round stops for this scan with its
        rows and position kept, and the next scan resumes it. Each round records what it is running -
        full, delta or resuming - on the scan row and the queue name.

        A tenant's drive tasks share one SharePoint throttle budget; three keep the lowest licence band
        busy without throttling and leave background slots for other work.

    .FUNCTIONALITY
        Entrypoint
    #>
    param($Item)

    $Parameters = $Item.Parameters
    $TenantFilter = [string]$Parameters.TenantFilter
    $ScanId = [string]$Parameters.ScanId
    $Round = [int]$Parameters.Round
    $ForceFull = [bool]$Parameters.ForceFull
    try {
        $StateTable = Get-CippTable -tablename 'CippSharingLinksState'
        $SafeTenant = ConvertTo-CIPPODataFilterValue -Value $TenantFilter -Type String
        $Scan = Get-CIPPAzDataTableEntity @StateTable -Filter "PartitionKey eq '$SafeTenant' and RowKey eq 'scan'"
        if ([string]$Scan.ScanId -ne $ScanId) { return }

        $Done = [System.Collections.Generic.HashSet[string]]::new()
        foreach ($Row in @(Get-CIPPAzDataTableEntity @StateTable -Filter "PartitionKey eq '$SafeTenant' and RowKey ge 'ddone-' and RowKey lt 'ddone-~'" -Property @('PartitionKey', 'RowKey', 'ScanId'))) {
            if ([string]$Row.ScanId -eq $ScanId) { [void]$Done.Add([string]$Row.RowKey) }
        }
        $Checkpoints = @{}
        foreach ($Row in @(Get-CIPPAzDataTableEntity @StateTable -Filter "PartitionKey eq '$SafeTenant' and RowKey ge 'chk-' and RowKey lt 'chk-~'")) {
            if ([string]$Row.ScanId -eq $ScanId) { $Checkpoints[[string]$Row.RowKey] = $Row }
        }
        $DriveStates = @{}
        foreach ($Row in @(Get-CIPPSharingLinksDriveState -TenantFilter $TenantFilter)) { if ($Row.DriveId) { $DriveStates[[string]$Row.DriveId] = $Row } }

        $Drives = foreach ($Site in @(Get-CIPPAzDataTableEntity @StateTable -Filter "PartitionKey eq '$SafeTenant' and RowKey ge 'drives-' and RowKey lt 'drives-~'")) {
            if ([string]$Site.ScanId -ne $ScanId -or -not $Site.DrivesJson) { continue }
            $SiteKey = ([string]$Site.RowKey).Substring('drives-'.Length)
            foreach ($Drive in @(ConvertFrom-Json -InputObject ([string]$Site.DrivesJson))) {
                $DriveKey = "$SiteKey~$([string]$Drive.id -replace '[/\\#?]', '_' -replace '[\u0000-\u001F\u007F-\u009F]', '')"
                if ($Done.Contains("ddone-$DriveKey")) { continue }
                $Checkpoint = $Checkpoints["chk-$DriveKey"]
                $State = $DriveStates[[string]$Drive.id]
                [PSCustomObject]@{
                    FunctionName    = 'DBCacheSharePointSiteSharingLinks'
                    TenantFilter    = $TenantFilter
                    SiteId          = [string]$Site.SiteId
                    SiteName        = [string]$Site.SiteName
                    SiteUrl         = [string]$Site.SiteUrl
                    IsPersonalSite  = [bool]$Site.IsPersonalSite
                    InternalDomains = @($Parameters.InternalDomains)
                    ScanId          = $ScanId
                    DriveId         = [string]$Drive.id
                    DriveName       = [string]$Drive.name
                    ReadRoot        = $Drive.readRoot -ne $false
                    ForceFull       = $ForceFull
                    QueueId         = $Parameters.QueueId
                    QueueName       = "Sharing Links - $($Drive.name) - $($Site.SiteUrl)"
                    # The mark left by the last round survives only if the task saved no page since.
                    Stalled         = $Round -gt 0 -and [bool]$Checkpoint.Dispatched
                    CheckpointKey   = "chk-$DriveKey"
                    Pass            = if ($Checkpoint.StateJson -or (-not $ForceFull -and $State.ResumeUri)) { 'resuming' } elseif (-not $ForceFull -and $State.DeltaLink -and $null -ne $State.RowCount) { 'delta' } else { 'full' }
                }
            }
        }
        $Drives = @($Drives)
        $Requeue = @($Drives.Where({ -not $_.Stalled }))
        foreach ($Drive in $Drives.Where({ $_.Stalled })) { $null = Push-DBCacheSharePointSiteSharingLinks -Item $Drive }
        if ($Requeue.Count -eq 0) { return }

        # Mark every drive going round again; a page saved by its task replaces the checkpoint and clears the mark.
        if ($Round -gt 0) {
            foreach ($Drive in $Requeue) {
                $Mark = $Checkpoints[$Drive.CheckpointKey] ?? [PSCustomObject]@{ PartitionKey = $TenantFilter; RowKey = $Drive.CheckpointKey; ScanId = $ScanId }
                $Mark | Add-Member -NotePropertyName Dispatched -NotePropertyValue $true -Force
                Add-CIPPAzDataTableEntity @StateTable -Entity $Mark -Force
            }
        }

        $Passes = @(foreach ($Pass in 'full', 'delta', 'resuming') { $N = $Requeue.Where({ $_.Pass -eq $Pass }).Count; if ($N) { "$N $Pass" } })
        $Phase = "Round $($Round + 1): $($Requeue.Count) $(if ($Requeue.Count -eq 1) { 'library' } else { 'libraries' }) ($($Passes -join ', '))"
        $Scan | Add-Member -NotePropertyName Phase -NotePropertyValue $Phase -Force
        Add-CIPPAzDataTableEntity @StateTable -Entity $Scan -Force
        if ($Parameters.QueueId) {
            try { Update-CippQueueEntry -RowKey $Parameters.QueueId -Name "Sharing links - $Phase" } catch {
                Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message "Sharing links: could not update queue $($Parameters.QueueId): $($_.Exception.Message)" -sev Debug
            }
        }
        if ($Round -gt 0) {
            Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message "Sharing links: $Phase still progressing after round $Round" -sev Info
        }

        $NextParameters = @{
            TenantFilter    = $TenantFilter
            ScanId          = $ScanId
            InternalDomains = @($Parameters.InternalDomains)
            ForceFull       = $ForceFull
            QueueId         = $Parameters.QueueId
            Round           = $Round + 1
        }
        $null = Start-CIPPOrchestrator -InputObject ([PSCustomObject]@{
                Batch            = $Requeue
                OrchestratorName = "SharingLinksDrives_$($TenantFilter)_r$($Round + 1)"
                MaxConcurrency   = 3
                SkipLog          = $true
                PostExecution    = @{
                    FunctionName = 'SharingLinksDispatchDrives'
                    Parameters   = $NextParameters
                }
            })
    } catch {
        Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message "Sharing links: failed queuing drive scans (round $($Round + 1)): $($_.Exception.Message)" -sev Error -LogData (Get-CippException -Exception $_)
    }
}
