function Get-CIPPIntuneReportExportJob {
    <#
    .SYNOPSIS
        Returns a tenant's completed Intune report export, or nothing if it is not ready. Never waits.
    .FUNCTIONALITY
        Internal
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$TenantFilter,

        [Parameter(Mandatory = $true)]
        [ValidateSet('AppInvRawData', 'AppInstallStatusAggregate', 'NoncompliantDevicesAndSettingsV3')]
        [string]$ReportName
    )

    $JobsTable = Get-CIPPTable -tablename 'IntuneReportJobs'
    $JobRow = Get-CIPPAzDataTableEntity @JobsTable -Filter "PartitionKey eq '$TenantFilter' and RowKey eq '$ReportName'"

    if (-not $JobRow) {
        $null = New-CIPPIntuneReportExportJob -TenantFilter $TenantFilter -ReportName $ReportName
        Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message "No $ReportName export job pending - submitted one" -sev Info
        return
    }

    if (-not $JobRow.JobId) {
        Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message 'IntuneReportJobs row missing JobId - removing' -sev Warning
        Remove-CIPPAzDataTableEntity @JobsTable -Entity $JobRow -Force -ErrorAction SilentlyContinue
        return
    }

    # Intune deletes the download 6 hours after the export completes
    if ($JobRow.SubmittedAt -and [datetimeoffset]$JobRow.SubmittedAt -lt [datetimeoffset]::UtcNow.AddHours(-6)) {
        Remove-CIPPAzDataTableEntity @JobsTable -Entity $JobRow -Force -ErrorAction SilentlyContinue
        $null = New-CIPPIntuneReportExportJob -TenantFilter $TenantFilter -ReportName $ReportName
        Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message "$ReportName job $($JobRow.JobId) expired before it was read - submitted a new one" -sev Info
        return
    }

    foreach ($Attempt in 1..3) {
        try {
            $Job = New-GraphGetRequest -uri "https://graph.microsoft.com/beta/deviceManagement/reports/exportJobs/$($JobRow.JobId)" -tenantid $TenantFilter
            break
        } catch {
            if ($Attempt -lt 3) {
                Start-Sleep -Seconds 5
                continue
            }
            # Intune returns 500 for jobs that read fine seconds later, so the row is kept for the next poll
            $ErrorMessage = Get-CippException -Exception $_
            Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message "$ReportName job $($JobRow.JobId) not retrievable: $($ErrorMessage.NormalizedError)" -sev Warning -LogData $ErrorMessage
            return
        }
    }

    if ($Job.status -eq 'completed' -and $Job.url) {
        return [pscustomobject]@{ JobId = $JobRow.JobId; Url = $Job.url; Row = $JobRow }
    }

    if ($Job.status -in 'completed', 'failed') {
        Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message "$ReportName job $($JobRow.JobId) $($Job.status) without a download url - removing" -sev Error
        Remove-CIPPAzDataTableEntity @JobsTable -Entity $JobRow -Force -ErrorAction SilentlyContinue
        return
    }

    Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message "$ReportName job $($JobRow.JobId) still '$($Job.status)'" -sev Debug
}
