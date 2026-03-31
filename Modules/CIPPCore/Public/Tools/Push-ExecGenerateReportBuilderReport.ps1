function Push-ExecGenerateReportBuilderReport {
    <#
    .FUNCTIONALITY
        Entrypoint
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $false)]
        [Alias('input')]
        $InputValue,
        $TenantFilter,
        $TemplateName,
        $Blocks,
        $TemplateGUID
    )

    try {
        if ([string]::IsNullOrEmpty($TenantFilter)) {
            throw 'TenantFilter is required'
        }

        # Parse Blocks
        $ParsedBlocks = @()
        if ($Blocks) {
            if ($Blocks -is [string]) {
                $ParsedBlocks = @(ConvertFrom-Json -InputObject $Blocks)
            } else {
                $ParsedBlocks = @($Blocks)
            }
        } elseif ($TemplateGUID) {
            $TemplateTable = Get-CippTable -tablename 'templates'
            $Template = Get-CIPPAzDataTableEntity @TemplateTable -Filter "PartitionKey eq 'ReportBuilderTemplate' and RowKey eq '$($TemplateGUID)'"
            if ($Template -and $Template.JSON) {
                $TemplateData = ConvertFrom-Json -InputObject $Template.JSON
                $ParsedBlocks = @($TemplateData.Blocks)
            }
        }

        if ($ParsedBlocks.Count -eq 0) {
            throw 'No blocks provided and no template found'
        }

        # For test blocks that are NOT static, fetch fresh test results
        $TestResults = $null
        $HasLiveTests = $ParsedBlocks | Where-Object { $_.type -eq 'test' -and $_.static -ne $true }
        if ($HasLiveTests) {
            $TestTable = Get-CippTable -tablename 'CippTestResults'
            $TestFilter = "PartitionKey eq '$TenantFilter'"
            $TestResults = @(Get-CIPPAzDataTableEntity @TestTable -Filter $TestFilter)
        }

        # Build enriched blocks with fresh content
        $EnrichedBlocks = @($ParsedBlocks | ForEach-Object {
                $Block = $_

                # Enrich live test blocks
                if ($Block.type -eq 'test' -and $Block.static -ne $true -and $TestResults) {
                    $TestResult = $TestResults | Where-Object { $_.TestId -eq $Block.testId -or $_.RowKey -eq $Block.testId } | Select-Object -First 1
                    if ($TestResult) {
                        if ($TestResult.TestType -eq 'Custom' -and $TestResult.ResultDataJson -and $TestResult.MarkdownTemplate) {
                            $Block.content = $TestResult.MarkdownTemplate
                        }
                        if (-not $Block.content -and $TestResult.ResultMarkdown) {
                            $Block | Add-Member -NotePropertyName 'content' -NotePropertyValue $TestResult.ResultMarkdown -Force
                        }
                    }
                }

                # Enrich database blocks
                if ($Block.type -eq 'database' -and $Block.dbType) {
                    try {
                        $DbData = New-CIPPDbRequest -TenantFilter $TenantFilter -Type $Block.dbType
                        if ($null -ne $DbData) {
                            $FirstItem = if ($DbData -is [array]) { $DbData[0] } else { $DbData }
                            $SelectedHeaders = @($Block.selectedHeaders)
                            if ($SelectedHeaders.Count -eq 0) {
                                $ExcludedHeaders = @('id', 'rowkey', 'partitionkey', 'etag', 'timestamp')
                                $AllHeaders = @($FirstItem.PSObject.Properties.Name | Where-Object { $_.ToLower() -notin $ExcludedHeaders }) | Sort-Object
                                $SelectedHeaders = $AllHeaders
                            }
                            $Format = if ($Block.format) { $Block.format } else { 'text' }
                            $FilteredData = @(@($DbData) | ForEach-Object {
                                    $Row = $_
                                    $Obj = [ordered]@{}
                                    foreach ($Header in $SelectedHeaders) {
                                        $Val = $Row.$Header
                                        $Obj[$Header] = if ($null -ne $Val) { $Val } else { '' }
                                    }
                                    [PSCustomObject]$Obj
                                })

                            $BlockContent = switch ($Format) {
                                'json' {
                                    ConvertTo-Json -InputObject @($FilteredData) -Depth 10 -Compress
                                }
                                'csv' {
                                    ($FilteredData | ConvertTo-Csv -NoTypeInformation) -join "`n"
                                }
                                default {
                                    $HeaderLine = '| ' + ($SelectedHeaders -join ' | ') + ' |'
                                    $SeparatorLine = '| ' + (($SelectedHeaders | ForEach-Object { '---' }) -join ' | ') + ' |'
                                    $DataLines = @($FilteredData | ForEach-Object {
                                            $DataRow = $_
                                            $Cells = $SelectedHeaders | ForEach-Object {
                                                $Val = $DataRow.$_
                                                if ($null -eq $Val) { '' }
                                                elseif ($Val -is [PSCustomObject] -or $Val -is [hashtable]) { ConvertTo-Json -InputObject $Val -Depth 5 -Compress }
                                                else { "$Val" -replace '\|', '\|' -replace "`n", ' ' }
                                            }
                                            '| ' + ($Cells -join ' | ') + ' |'
                                        })
                                    (@($HeaderLine, $SeparatorLine) + $DataLines) -join "`n"
                                }
                            }
                            $Block | Add-Member -NotePropertyName 'content' -NotePropertyValue $BlockContent -Force
                            $Block | Add-Member -NotePropertyName 'static' -NotePropertyValue $true -Force
                        } else {
                            $Block | Add-Member -NotePropertyName 'content' -NotePropertyValue 'No data available for this data source.' -Force
                        }
                    } catch {
                        $DbError = Get-CippException -Exception $_
                        Write-LogMessage -API 'ReportBuilder' -tenant $TenantFilter -message "Failed to fetch database data for type $($Block.dbType): $($DbError.NormalizedError)" -Sev 'Warning' -LogData $DbError
                        $Block | Add-Member -NotePropertyName 'content' -NotePropertyValue "Error fetching data: $($DbError.NormalizedError)" -Force
                    }
                }

                $Block
            })

        # Store the generated report
        $ReportGUID = (New-Guid).GUID
        $ReportTable = Get-CippTable -tablename 'ReportBuilderReports'
        $ReportEntity = @{
            PartitionKey = $TenantFilter
            RowKey       = [string]$ReportGUID
            TemplateName = [string]($TemplateName ?? 'Scheduled Report')
            TenantFilter = [string]$TenantFilter
            Blocks       = [string](ConvertTo-Json -InputObject @($EnrichedBlocks) -Depth 20 -Compress)
            GeneratedAt  = [string](Get-Date).ToString('o')
            Status       = 'Completed'
        }

        Add-CIPPAzDataTableEntity @ReportTable -Entity $ReportEntity -Force
        Write-LogMessage -API 'ReportBuilder' -tenant $TenantFilter -message "Generated report builder report '$TemplateName' with GUID $ReportGUID" -Sev 'Info'

        return "Successfully generated report '$TemplateName' for $TenantFilter (GUID: $ReportGUID)"
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Write-LogMessage -API 'ReportBuilder' -tenant $TenantFilter -message "Report generation error: $($ErrorMessage.NormalizedError)" -Sev 'Error' -LogData $ErrorMessage
        return "Error generating report: $($ErrorMessage.NormalizedError)"
    }
}
