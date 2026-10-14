function Push-SharingLinksDispatchDrives {
    <#
    .SYNOPSIS
        Post-execution for a tenant's sharing-links site run: queues every drive task as one run

    .DESCRIPTION
        A tenant's drive tasks share one SharePoint throttle budget, so past two at once they only
        hold background slots waiting on the pacer.

    .FUNCTIONALITY
        Entrypoint
    #>
    param($Item)

    $TenantFilter = $Item.Parameters.TenantFilter
    $Drives = @(foreach ($Result in @($Item.Results)) { foreach ($Drive in @($Result)) { if ($Drive.DriveId) { $Drive } } })
    if ($Drives.Count -eq 0) { return }
    try {
        $null = Start-CIPPOrchestrator -InputObject ([PSCustomObject]@{
                Batch            = $Drives
                OrchestratorName = "SharingLinksDrives_$TenantFilter"
                MaxConcurrency   = 2
                SkipLog          = $true
            })
    } catch {
        Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message "Sharing links: failed queuing $($Drives.Count) drive scans: $($_.Exception.Message)" -sev Error -LogData (Get-CippException -Exception $_)
    }
}
