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
        [ValidateSet('AppInvRawData', 'AppInstallStatusAggregate')]
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

    try {
        $Job = New-GraphGetRequest -uri "https://graph.microsoft.com/beta/deviceManagement/reports/exportJobs/$($JobRow.JobId)" -tenantid $TenantFilter
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message "$ReportName job $($JobRow.JobId) not retrievable: $($ErrorMessage.NormalizedError)" -sev Warning -LogData $ErrorMessage
        Remove-CIPPAzDataTableEntity @JobsTable -Entity $JobRow -Force -ErrorAction SilentlyContinue
        return
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
