function Push-IntuneReportExportSubmit {
    <#
    .SYNOPSIS
        Submits an Intune report export job for a tenant and stores the job id.
    .FUNCTIONALITY
        Entrypoint
    #>
    [CmdletBinding()]
    param($Item)

    $TenantFilter = $Item.TenantFilter
    $ReportName   = $Item.ReportName

    if (-not $TenantFilter -or -not $ReportName) {
        Write-LogMessage -API 'IntuneReportExport' -message 'Missing TenantFilter or ReportName on activity item' -sev Error
        return @{ Status = 'Failed'; Reason = 'MissingInput' }
    }

    try {
        $Job = New-CIPPIntuneReportExportJob -TenantFilter $TenantFilter -ReportName $ReportName

        Write-LogMessage -API 'IntuneReportExport' -tenant $TenantFilter -message "Submitted $ReportName export job $($Job.id)" -sev Info
        return @{ Status = 'Submitted'; JobId = $Job.id; ReportName = $ReportName; TenantFilter = $TenantFilter }
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Write-LogMessage -API 'IntuneReportExport' -tenant $TenantFilter -message "Failed to submit $ReportName export: $($ErrorMessage.NormalizedError)" -sev Error -LogData $ErrorMessage
        return @{ Status = 'Failed'; ReportName = $ReportName; TenantFilter = $TenantFilter; Error = $ErrorMessage.NormalizedError }
    }
}
