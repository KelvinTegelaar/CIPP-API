function Start-IntuneReportExportOrchestrator {
    <#
    .SYNOPSIS
        Submits Intune report-export jobs at 02:00 UTC ahead of the 03:00 cache run.
    .FUNCTIONALITY
        Entrypoint
    #>
    [CmdletBinding()]
    param()

    try {
        Write-LogMessage -API 'IntuneReportExport' -message 'Starting Intune report export submission' -sev Info

        $TenantList = Get-Tenants | Where-Object { $_.defaultDomainName -ne $null }
        if ($TenantList.Count -eq 0) {
            return
        }

        $LicensedTenants = @(foreach ($Tenant in $TenantList) {
            try {
                if (Test-CIPPStandardLicense -StandardName 'IntuneReportExportSubmission' -TenantFilter $Tenant.defaultDomainName -Preset Intune -SkipLog) {
                    $Tenant
                }
            } catch {
                $ErrorMessage = Get-CippException -Exception $_
                Write-LogMessage -API 'IntuneReportExport' -tenant $Tenant.defaultDomainName -message "Intune license check failed: $($ErrorMessage.NormalizedError)" -sev Warning -LogData $ErrorMessage
            }
        })

        if ($LicensedTenants.Count -eq 0) {
            return
        }

        $ReportNames = @('AppInvRawData', 'AppInstallStatusAggregate')

        $Queue = New-CippQueueEntry -Name 'Intune Report Export Submission' -TotalTasks ($LicensedTenants.Count * $ReportNames.Count)

        $Batch = foreach ($Tenant in $LicensedTenants) {
            foreach ($ReportName in $ReportNames) {
                [PSCustomObject]@{
                    FunctionName = 'IntuneReportExportSubmit'
                    TenantFilter = $Tenant.defaultDomainName
                    ReportName   = $ReportName
                    QueueId      = $Queue.RowKey
                    QueueName    = "Intune Export Submit ($ReportName) - $($Tenant.defaultDomainName)"
                }
            }
        }

        Start-CIPPOrchestrator -InputObject ([PSCustomObject]@{
            Batch            = @($Batch)
            OrchestratorName = 'IntuneReportExportOrchestrator'
            SkipLog          = $false
        })

    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Write-LogMessage -API 'IntuneReportExport' -message "Failed to start orchestration: $($ErrorMessage.NormalizedError)" -sev Error -LogData $ErrorMessage
        throw
    }
}
