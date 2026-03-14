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
        $CustomTotal = 0
        $IdentityTests = @()
        $DevicesTests = @()
        $CustomTests = @()

        $NormalizeTestIds = {
            param($Value)

            if ($null -eq $Value) {
                return @()
            }

            if ($Value -is [string]) {
                return @($Value)
            }

            if ($Value -is [System.Collections.IEnumerable] -and $Value -isnot [string]) {
                return @($Value | ForEach-Object {
                        if ($_ -is [pscustomobject] -and $_.PSObject.Properties['id']) {
                            [string]$_.id
                        } else {
                            [string]$_
                        }
                    })
            }

            return @([string]$Value)
        }

        if ($ReportId) {
            $ReportJsonFiles = Get-ChildItem 'Modules\CIPPCore\Public\Tests\*\report.json' -ErrorAction SilentlyContinue
            $ReportFound = $false

            $MatchingReport = $ReportJsonFiles | Where-Object { $_.Directory.Name.ToLower() -eq $ReportId.ToLower() } | Select-Object -First 1

            if ($MatchingReport) {
                try {
                    $ReportContent = Get-Content $MatchingReport.FullName -Raw | ConvertFrom-Json
                    if ($ReportContent.IdentityTests) {
                        $IdentityTests = & $NormalizeTestIds $ReportContent.IdentityTests
                        $IdentityTotal = @($IdentityTests).Count
                    }
                    if ($ReportContent.DevicesTests) {
                        $DevicesTests = & $NormalizeTestIds $ReportContent.DevicesTests
                        $DevicesTotal = @($DevicesTests).Count
                    }
                    if ($ReportContent.CustomTests) {
                        $CustomTests = & $NormalizeTestIds $ReportContent.CustomTests
                        $CustomTotal = @($CustomTests).Count
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
                        $IdentityTests = & $NormalizeTestIds ($ReportTemplate.identityTests | ConvertFrom-Json)
                        $IdentityTotal = @($IdentityTests).Count
                    }

                    if ($ReportTemplate.DevicesTests) {
                        $DevicesTests = & $NormalizeTestIds ($ReportTemplate.DevicesTests | ConvertFrom-Json)
                        $DevicesTotal = @($DevicesTests).Count
                    }

                    if ($ReportTemplate.CustomTests) {
                        $CustomTests = & $NormalizeTestIds ($ReportTemplate.CustomTests | ConvertFrom-Json)
                        $CustomTotal = @($CustomTests).Count
                    }
                    $ReportFound = $true
                } else {
                    Write-LogMessage -API $APIName -tenant $TenantFilter -message "Report template '$ReportId' not found" -sev Warning
                }
            }

            # Filter tests if report was found
            if ($ReportFound) {
                $AllReportTests = @($IdentityTests) + @($DevicesTests) + @($CustomTests)
                # Use HashSet for O(1) lookup performance
                $TestLookup = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
                foreach ($test in $AllReportTests) {
                    if (-not [string]::IsNullOrWhiteSpace($test)) {
                        [void]$TestLookup.Add([string]$test)
                    }
                }
                $FilteredTests = $TestResultsData.TestResults | Where-Object { $TestLookup.Contains($_.RowKey) }
                $TestResultsData.TestResults = @($FilteredTests)
            } else {
                $TestResultsData.TestResults = @()
            }
        } else {
            $IdentityTotal = @($TestResultsData.TestResults | Where-Object { $_.TestType -eq 'Identity' }).Count
            $DevicesTotal = @($TestResultsData.TestResults | Where-Object { $_.TestType -eq 'Devices' }).Count
            $CustomTotal = @($TestResultsData.TestResults | Where-Object { $_.TestType -eq 'Custom' }).Count
        }

        $IdentityResults = $TestResultsData.TestResults | Where-Object { $_.TestType -eq 'Identity' }
        $DeviceResults = $TestResultsData.TestResults | Where-Object { $_.TestType -eq 'Devices' }
        $CustomResultsForCounts = $TestResultsData.TestResults | Where-Object { $_.TestType -eq 'Custom' }

        # Build lookup of custom script metadata (latest version per ScriptGuid)
        $CustomScriptMetadataLookup = @{}
        $CustomResults = @($TestResultsData.TestResults | Where-Object { $_.TestType -eq 'Custom' })
        if ($CustomResults.Count -gt 0) {
            $CustomScriptsTable = Get-CippTable -tablename 'CustomPowershellScripts'
            $CustomScripts = @(Get-CIPPAzDataTableEntity @CustomScriptsTable -Filter "PartitionKey eq 'CustomScript'")

            if ($CustomScripts.Count -gt 0) {
                $LatestCustomScripts = $CustomScripts |
                    Group-Object -Property ScriptGuid |
                    ForEach-Object {
                        $_.Group | Sort-Object -Property Version -Descending | Select-Object -First 1
                    }

                foreach ($Script in @($LatestCustomScripts)) {
                    if (-not [string]::IsNullOrWhiteSpace($Script.ScriptGuid)) {
                        $CustomScriptMetadataLookup[$Script.ScriptGuid] = [PSCustomObject]@{
                            Description      = $Script.Description ?? ''
                            ReturnType       = $Script.ReturnType ?? 'JSON'
                            MarkdownTemplate = $Script.MarkdownTemplate ?? ''
                        }
                    }
                }
            }
        }

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

            if ($TestResult.TestType -eq 'Custom') {
                $ScriptGuid = ($TestResult.RowKey -replace '^CustomScript-', '')
                if (-not [string]::IsNullOrWhiteSpace($ScriptGuid) -and $CustomScriptMetadataLookup.ContainsKey($ScriptGuid)) {
                    $CustomMetadata = $CustomScriptMetadataLookup[$ScriptGuid]
                    $TestResult | Add-Member -NotePropertyName 'Description' -NotePropertyValue ($CustomMetadata.Description) -Force
                    $TestResult | Add-Member -NotePropertyName 'ReturnType' -NotePropertyValue ($CustomMetadata.ReturnType) -Force
                    $TestResult | Add-Member -NotePropertyName 'MarkdownTemplate' -NotePropertyValue ($CustomMetadata.MarkdownTemplate) -Force
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
            Custom   = @{
                Passed      = @($CustomResultsForCounts | Where-Object { $_.Status -eq 'Passed' }).Count
                Failed      = @($CustomResultsForCounts | Where-Object { $_.Status -eq 'Failed' }).Count
                Investigate = @($CustomResultsForCounts | Where-Object { $_.Status -eq 'Investigate' }).Count
                Skipped     = @($CustomResultsForCounts | Where-Object { $_.Status -eq 'Skipped' }).Count
                Total       = $CustomTotal
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
