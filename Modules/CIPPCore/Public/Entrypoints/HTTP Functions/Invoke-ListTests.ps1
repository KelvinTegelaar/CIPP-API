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

        $IdentityTotal = 0
        $DevicesTotal = 0

        if ($ReportId) {
            $ReportTable = Get-CippTable -tablename 'CippReportTemplates'
            $Filter = "PartitionKey eq 'ReportingTemplate' and RowKey eq '{0}'" -f $ReportId
            $ReportTemplate = Get-CIPPAzDataTableEntity @ReportTable -Filter $Filter

            if ($ReportTemplate) {
                $IdentityTests = @()
                $DeviceTests = @()

                if ($ReportTemplate.identityTests) {
                    $IdentityTests = $ReportTemplate.identityTests | ConvertFrom-Json
                    $IdentityTotal = @($IdentityTests).Count
                }

                if ($ReportTemplate.deviceTests) {
                    $DeviceTests = $ReportTemplate.deviceTests | ConvertFrom-Json
                    $DevicesTotal = @($DeviceTests).Count
                }

                $AllReportTests = $IdentityTests + $DeviceTests
                $FilteredTests = $TestResultsData.TestResults | Where-Object { $AllReportTests -contains $_.RowKey }
                $TestResultsData.TestResults = @($FilteredTests)
            } else {
                Write-LogMessage -API $APIName -tenant $TenantFilter -message "Report template '$ReportId' not found" -sev Warning
                $TestResultsData.TestResults = @()
            }
        } else {
            $IdentityTotal = @($TestResultsData.TestResults | Where-Object { $_.TestType -eq 'Identity' }).Count
            $DevicesTotal = @($TestResultsData.TestResults | Where-Object { $_.TestType -eq 'Devices' }).Count
        }

        $IdentityResults = $TestResultsData.TestResults | Where-Object { $_.TestType -eq 'Identity' }
        $DeviceResults = $TestResultsData.TestResults | Where-Object { $_.TestType -eq 'Devices' }

        $TestCounts = @{
            Identity = @{
                Passed      = @($IdentityResults | Where-Object { $_.Status -eq 'Passed' }).Count
                Failed      = @($IdentityResults | Where-Object { $_.Status -eq 'Failed' }).Count
                Investigate = @($IdentityResults | Where-Object { $_.Status -eq 'Investigate' }).Count
                Skipped     = @($IdentityResults | Where-Object { $_.Status -eq 'Skipped' }).Count
                Total       = $IdentityTotal
            }
            Devices  = @{
                Passed      = @($DeviceResults | Where-Object { $_.Status -eq 'Passed' }).Count
                Failed      = @($DeviceResults | Where-Object { $_.Status -eq 'Failed' }).Count
                Investigate = @($DeviceResults | Where-Object { $_.Status -eq 'Investigate' }).Count
                Skipped     = @($DeviceResults | Where-Object { $_.Status -eq 'Skipped' }).Count
                Total       = $DevicesTotal
            }
        }

        $TestResultsData | Add-Member -NotePropertyName 'TestCounts' -NotePropertyValue $TestCounts -Force

        $SecureScoreData = New-CIPPDbRequest -TenantFilter $TenantFilter -Type 'SecureScore'
        if ($SecureScoreData) {
            $TestResultsData | Add-Member -NotePropertyName 'SecureScore' -NotePropertyValue $SecureScoreData -Force
        }

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
