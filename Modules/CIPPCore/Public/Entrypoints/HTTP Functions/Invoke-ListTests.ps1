function Invoke-ListTests {
    <#
    .SYNOPSIS
        Lists tests for a tenant, optionally filtered by report ID

    .FUNCTIONALITY
        Entrypoint

    .ROLE
        Tenant.Reports.Read
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $APIName = $TriggerMetadata.FunctionName
    Write-LogMessage -user $request.headers.'x-ms-client-principal' -API $APINAME -message 'Accessed this API' -Sev 'Debug'

    try {
        $TenantFilter = $Request.Query.tenantFilter ?? $Request.Body.tenantFilter
        $ReportId = $Request.Query.reportId ?? $Request.Body.reportId

        if (-not $TenantFilter) {
            throw 'TenantFilter parameter is required'
        }

        $TestResultsData = Get-CIPPTestResults -TenantFilter $TenantFilter

        $TotalTests = 0

        if ($ReportId) {
            $ReportTable = Get-CippTable -tablename 'CippReportTemplates'
            $Filter = "PartitionKey eq 'ReportingTemplate' and RowKey eq '{0}'" -f $ReportId
            $ReportTemplate = Get-CIPPAzDataTableEntity @ReportTable -Filter $Filter

            if ($ReportTemplate) {
                $ReportTests = $ReportTemplate.Tests | ConvertFrom-Json
                $TotalTests = @($ReportTests).Count
                $FilteredTests = $TestResultsData.TestResults | Where-Object { $ReportTests -contains $_.TestId }
                $TestResultsData.TestResults = $FilteredTests
            } else {
                Write-LogMessage -API $APIName -tenant $TenantFilter -message "Report template '$ReportId' not found" -sev Warning
                $TestResultsData.TestResults = @()
            }
        } else {
            $TotalTests = @($TestResultsData.TestResults).Count
        }

        $TestCounts = @{
            Successful = @($TestResultsData.TestResults | Where-Object { $_.Result -eq 'Passed' }).Count
            Failed     = @($TestResultsData.TestResults | Where-Object { $_.Result -eq 'Failed' }).Count
            Skipped    = @($TestResultsData.TestResults | Where-Object { $_.Result -eq 'Skipped' }).Count
            Total      = $TotalTests
        }

        $TestResultsData | Add-Member -NotePropertyName 'TestCounts' -NotePropertyValue $TestCounts -Force

        $StatusCode = [HttpStatusCode]::OK
        $Body = $TestResultsData

    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Write-LogMessage -API $APIName -tenant $TenantFilter -message "Error retrieving tests: $($ErrorMessage.NormalizedError)" -sev Error -LogData $ErrorMessage
        $StatusCode = [HttpStatusCode]::BadRequest
        $Body = @{ Error = $ErrorMessage.NormalizedError }
    }

    Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
            StatusCode = $StatusCode
            Body       = $Body
        })
}
