function Start-CIPPManagedBaselineSyncTimer {
    <#
    .SYNOPSIS
        Hourly check on the custom managed baseline requests that are waiting on CyberDrain.
    .DESCRIPTION
        Does nothing, and calls nothing, unless the Managed Baselines integration is enabled
        and a request is open. Asks CyberDrain about each request that was sent, repeats a
        confirm call that failed earlier, looks once a day for a newer version of a delivered
        baseline, and marks a data collection that never finished as failed so it can be retried.
    #>
    [CmdletBinding(SupportsShouldProcess = $true)]
    param()

    if (-not $PSCmdlet.ShouldProcess('Start-CIPPManagedBaselineSyncTimer', 'Checking managed baseline requests')) { return }

    $ConfigTable = Get-CippTable -tablename 'Extensionsconfig'
    $Config = $(try { (Get-CIPPAzDataTableEntity @ConfigTable).config | ConvertFrom-Json -ErrorAction Stop } catch { $null })
    if ($Config.CyberDrainManagedBaselines.Enabled -ne $true) { return }

    $Table = Get-CippTable -tablename 'ManagedBaselineRequests'
    $Now = [int64]([datetimeoffset]::UtcNow.ToUnixTimeSeconds())
    foreach ($Row in @(Get-CIPPAzDataTableEntity @Table -Filter "PartitionKey eq 'request'")) {
        $Status = "$($Row.Status)"
        if ($Status -eq 'Waiting on data collection') {
            # A collection takes minutes; one still open after six hours lost its run.
            if ([int64]($Row.CollectionStartedAt ?? 0) -lt ($Now - 21600)) {
                Add-CIPPAzDataTableEntity @Table -Entity @{
                    PartitionKey = 'request'
                    RowKey       = "$($Row.RowKey)"
                    Status       = 'Failed'
                    Error        = 'Data collection did not finish. Use Retry to start it again.'
                } -OperationType UpsertMerge
            }
            continue
        }
        $Due = $Status -in @('Waiting on CyberDrain', 'Completed - ready to confirm') -or $Row.ConfirmPending -eq $true -or
            ($Status -eq 'Implemented' -and [int64]($Row.LastChecked ?? 0) -lt ($Now - 86400))
        if (-not $Due) { continue }
        try {
            $null = Update-CIPPManagedBaselineRequest -Row $Row
        } catch [System.UnauthorizedAccessException] {
            # A rejected key is rejected for every request: say so once and stop asking.
            Write-LogMessage -API 'ManagedBaselines' -message "Managed baseline requests could not be checked: $($_.Exception.Message)" -Sev 'Error'
            break
        } catch {
            Write-Information "Managed baseline request $($Row.RowKey) could not be checked: $($_.Exception.Message)"
        }
    }
}
