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

    try {
        $TenantFilter = $Request.Query.tenantFilter ?? $Request.Body.tenantFilter
        $ReportId = $Request.Query.reportId ?? $Request.Body.reportId

        if (-not $TenantFilter) {
            throw 'TenantFilter parameter is required'
        }

        $TestResultsData = Get-CIPPTestResults -TenantFilter $TenantFilter

        $IdentityTotal = 0
        $DevicesTotal = 0
        $IdentityTests = @()
        $DevicesTests = @()

        if ($ReportId) {
            $ReportJsonFiles = Get-ChildItem 'Modules\CIPPCore\Public\Tests\*\report.json' -ErrorAction SilentlyContinue
            $ReportFound = $false

            $MatchingReport = $ReportJsonFiles | Where-Object { $_.Directory.Name.ToLower() -eq $ReportId.ToLower() } | Select-Object -First 1

            if ($MatchingReport) {
                try {
                    $ReportContent = Get-Content $MatchingReport.FullName -Raw | ConvertFrom-Json
                    if ($ReportContent.IdentityTests) {
                        $IdentityTests = $ReportContent.IdentityTests
                        $IdentityTotal = @($IdentityTests).Count
                    }
                    if ($ReportContent.DevicesTests) {
                        $DevicesTests = $ReportContent.DevicesTests
                        $DevicesTotal = @($DevicesTests).Count
                    }
                    $ReportFound = $true
                } catch {
                    Write-LogMessage -API $APIName -tenant $TenantFilter -message "Error reading report.json: $($_.Exception.Message)" -sev Warning
                }
            }

            # Fall back to database if not found in JSON files
            if (-not $ReportFound) {
                $ReportTable = Get-CippTable -tablename 'CippReportTemplates'
                $Filter = "PartitionKey eq 'Report' and RowKey eq '{0}'" -f $ReportId
                $ReportTemplate = Get-CIPPAzDataTableEntity @ReportTable -Filter $Filter

                if ($ReportTemplate) {
                    if ($ReportTemplate.identityTests) {
                        $IdentityTests = $ReportTemplate.identityTests | ConvertFrom-Json
                        $IdentityTotal = @($IdentityTests).Count
                    }

                    if ($ReportTemplate.DevicesTests) {
                        $DevicesTests = $ReportTemplate.DevicesTests | ConvertFrom-Json
                        $DevicesTotal = @($DevicesTests).Count
                    }
                    $ReportFound = $true
                } else {
                    Write-LogMessage -API $APIName -tenant $TenantFilter -message "Report template '$ReportId' not found" -sev Warning
                }
            }

            # Filter tests if report was found
            if ($ReportFound) {
                $AllReportTests = $IdentityTests + $DevicesTests
                # Use HashSet for O(1) lookup performance
                $TestLookup = [System.Collections.Generic.HashSet[string]]::new()
                foreach ($test in $AllReportTests) {
                    [void]$TestLookup.Add($test)
                }
                $FilteredTests = $TestResultsData.TestResults | Where-Object { $TestLookup.Contains($_.RowKey) }
                $TestResultsData.TestResults = @($FilteredTests)
            } else {
                $TestResultsData.TestResults = @()
            }
        } else {
            $IdentityTotal = @($TestResultsData.TestResults | Where-Object { $_.TestType -eq 'Identity' }).Count
            $DevicesTotal = @($TestResultsData.TestResults | Where-Object { $_.TestType -eq 'Devices' }).Count
        }

        $IdentityResults = $TestResultsData.TestResults | Where-Object { $_.TestType -eq 'Identity' }
        $DeviceResults = $TestResultsData.TestResults | Where-Object { $_.TestType -eq 'Devices' }

        # Add descriptions from markdown files to each test result
        foreach ($TestResult in $TestResultsData.TestResults) {
            $MdFile = Get-ChildItem -Path 'Modules\CIPPCore\Public\Tests' -Filter "*$($TestResult.RowKey).md" -Recurse -ErrorAction SilentlyContinue | Select-Object -First 1
            if ($MdFile) {
                try {
                    $MdContent = Get-Content $MdFile.FullName -Raw -ErrorAction SilentlyContinue
                    if ($MdContent) {
                        $Description = ($MdContent -split '<!--- Results --->')[0].Trim()
                        $Description = ($Description -split '%TestResult%')[0].Trim()
                        $TestResult | Add-Member -NotePropertyName 'Description' -NotePropertyValue $Description -Force
                    }
                } catch {
                    #Test
                }
            }
        }

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
            $TestResultsData | Add-Member -NotePropertyName 'SecureScore' -NotePropertyValue @($SecureScoreData) -Force
        }
        $MFAStateData = New-CIPPDbRequest -TenantFilter $TenantFilter -Type 'MFAState'
        if ($MFAStateData) {
            $TestResultsData | Add-Member -NotePropertyName 'MFAState' -NotePropertyValue @($MFAStateData) -Force
        }

        $LicenseData = New-CIPPDbRequest -TenantFilter $TenantFilter -Type 'LicenseOverview'
        if ($LicenseData) {
            $TestResultsData | Add-Member -NotePropertyName 'LicenseData' -NotePropertyValue @($LicenseData) -Force
        }

        $StatusCode = [HttpStatusCode]::OK
        $Body = $TestResultsData

    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Write-LogMessage -API $APIName -tenant $TenantFilter -message "Error retrieving tests: $($ErrorMessage.NormalizedError)" -sev Error -LogData $ErrorMessage
        $StatusCode = [HttpStatusCode]::BadRequest
        $Body = @{ Error = $ErrorMessage.NormalizedError }
    }

    return ([HttpResponseContext]@{
            StatusCode = $StatusCode
            Body       = $Body
        })
}
