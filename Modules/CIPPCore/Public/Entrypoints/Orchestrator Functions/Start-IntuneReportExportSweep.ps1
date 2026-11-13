function Start-IntuneReportExportSweep {
    <#
    .SYNOPSIS
        Reads Intune report exports that are still waiting in IntuneReportJobs.
    .DESCRIPTION
        A row is removed once its export is read, so any row left is data the nightly cache still owes:
        an export submitted during the cache run, or one Intune failed to return the first time.
        The download expires 6 hours after the export completes, so this runs more often than that.
        Rows under 2 hours old are left to the cache run that the pre-submission is waiting for.
    .FUNCTIONALITY
        Entrypoint
    #>
    [CmdletBinding()]
    param()

    try {
        $JobsTable = Get-CIPPTable -tablename 'IntuneReportJobs'
        $Cutoff = [datetimeoffset]::UtcNow.AddHours(-2)
        $Rows = @(Get-CIPPAzDataTableEntity @JobsTable -Property PartitionKey, RowKey, SubmittedAt)
        if ($Rows.Count -eq 0) { return }

        $Batch = foreach ($Row in $Rows) {
            if ($Row.SubmittedAt -and [datetimeoffset]$Row.SubmittedAt -gt $Cutoff) { continue }
            $Name = switch ($Row.RowKey) {
                'AppInvRawData' { 'DetectedApps' }
                'AppInstallStatusAggregate' { 'IntuneAppInstallStatus' }
                'NoncompliantDevicesAndSettingsV3' { 'IntuneNonCompliantSettings' }
            }
            if (-not $Name) { continue }
            [PSCustomObject]@{
                FunctionName = 'ExecCIPPDBCache'
                Name         = $Name
                TenantFilter = $Row.PartitionKey
                QueueName    = "Intune Export Read ($Name) - $($Row.PartitionKey)"
            }
        }
        if (-not $Batch) { return }

        Start-CIPPOrchestrator -InputObject ([PSCustomObject]@{
            Batch            = @($Batch)
            OrchestratorName = 'IntuneReportExportSweep'
            Priority         = 10
            SkipLog          = $true
        })
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Write-LogMessage -API 'IntuneReportExport' -message "Failed to start the export sweep: $($ErrorMessage.NormalizedError)" -sev Error -LogData $ErrorMessage
        throw
    }
}
