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
        $Select = switch ($ReportName) {
            'AppInvRawData' {
                @(
                    'ApplicationKey', 'ApplicationName', 'ApplicationPublisher', 'ApplicationVersion',
                    'DeviceId', 'DeviceName', 'OSDescription', 'OSVersion', 'Platform',
                    'UserId', 'UserName', 'EmailAddress'
                )
            }
            default { throw "Unknown Intune report '$ReportName'" }
        }

        $Body = @{
            reportName       = $ReportName
            format           = 'json'
            localizationType = 'replaceLocalizableValues'
            select           = $Select
        } | ConvertTo-Json -Depth 5

        $Job = New-GraphPOSTRequest `
            -uri 'https://graph.microsoft.com/beta/deviceManagement/reports/exportJobs' `
            -tenantid $TenantFilter `
            -body $Body

        if (-not $Job.id) { throw "Intune returned no job id for $ReportName" }

        $JobsTable = Get-CIPPTable -tablename 'IntuneReportJobs'
        $Existing = Get-CIPPAzDataTableEntity @JobsTable -Filter "PartitionKey eq '$TenantFilter' and RowKey eq '$ReportName'"
        if ($Existing) {
            Remove-AzDataTableEntity @JobsTable -Entity $Existing -Force -ErrorAction SilentlyContinue
        }

        Add-CIPPAzDataTableEntity @JobsTable -Entity @{
            PartitionKey = $TenantFilter
            RowKey       = $ReportName
            JobId        = $Job.id
            ReportName   = $ReportName
            SubmittedAt  = ([DateTime]::UtcNow).ToString('o')
        } -Force

        Write-LogMessage -API 'IntuneReportExport' -tenant $TenantFilter -message "Submitted $ReportName export job $($Job.id)" -sev Info
        return @{ Status = 'Submitted'; JobId = $Job.id; ReportName = $ReportName; TenantFilter = $TenantFilter }
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Write-LogMessage -API 'IntuneReportExport' -tenant $TenantFilter -message "Failed to submit $ReportName export: $($ErrorMessage.NormalizedError)" -sev Error -LogData $ErrorMessage
        return @{ Status = 'Failed'; ReportName = $ReportName; TenantFilter = $TenantFilter; Error = $ErrorMessage.NormalizedError }
    }
}
