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

        # Build enriched blocks with fresh content for live test blocks
        $EnrichedBlocks = @($ParsedBlocks | ForEach-Object {
                $Block = $_
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
