function Invoke-ExecGenerateReportBuilderReport {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        CIPP.Core.ReadWrite
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $APIName = $TriggerMetadata.FunctionName
    $Headers = $Request.Headers

    try {
        $Body = $Request.Body
        $Action = $Body.Action

        if ($Action -eq 'delete') {
            if ([string]::IsNullOrEmpty($Body.ReportGUID)) {
                throw 'ReportGUID is required for deletion'
            }
            $ReportTable = Get-CippTable -tablename 'ReportBuilderReports'
            $ExistingEntity = Get-CIPPAzDataTableEntity @ReportTable -Filter "RowKey eq '$($Body.ReportGUID)'"
            if ($ExistingEntity) {
                Remove-AzDataTableEntity @ReportTable -Entity $ExistingEntity
                Write-LogMessage -headers $Headers -API $APIName -message "Deleted generated report '$($Body.ReportGUID)'" -Sev 'Info'
                $Result = @{ Results = 'Successfully deleted generated report' }
            } else {
                $Result = @{ Results = 'Report not found' }
            }
            $StatusCode = [HttpStatusCode]::OK
        } else {

            $TenantFilter = $Body.TenantFilter ?? $Request.Query.TenantFilter
            $TemplateName = $Body.TemplateName ?? $Request.Query.TemplateName

            if ([string]::IsNullOrEmpty($TenantFilter)) {
                throw 'TenantFilter is required'
            }

            # Parse Blocks from the request (or from a named template lookup)
            $Blocks = @()
            if ($Body.Blocks) {
                if ($Body.Blocks -is [string]) {
                    $Blocks = @(ConvertFrom-Json -InputObject $Body.Blocks)
                } else {
                    $Blocks = @($Body.Blocks)
                }
            } elseif ($Body.TemplateGUID) {
                # Look up template by GUID
                $TemplateTable = Get-CippTable -tablename 'ReportBuilderTemplates'
                $Template = Get-CIPPAzDataTableEntity @TemplateTable -Filter "PartitionKey eq 'ReportBuilderTemplate' and RowKey eq '$($Body.TemplateGUID)'"
                if ($Template -and $Template.Blocks) {
                    $Blocks = @(ConvertFrom-Json -InputObject $Template.Blocks)
                }
            }

            if ($Blocks.Count -eq 0) {
                throw 'No blocks provided and no template found'
            }

            # For test blocks that are NOT static, fetch fresh test results
            $TestResults = $null
            $HasLiveTests = $Blocks | Where-Object { $_.type -eq 'test' -and $_.static -ne $true }
            if ($HasLiveTests) {
                # Fetch current test results for this tenant
                $TestTable = Get-CippTable -tablename 'CippTestResults'
                $TestFilter = "PartitionKey eq '$TenantFilter'"
                $TestResults = @(Get-CIPPAzDataTableEntity @TestTable -Filter $TestFilter)
            }

            # Build enriched blocks with fresh content for live test blocks
            $EnrichedBlocks = @($Blocks | ForEach-Object {
                    $Block = $_
                    if ($Block.type -eq 'test' -and $Block.static -ne $true -and $TestResults) {
                        $TestResult = $TestResults | Where-Object { $_.TestId -eq $Block.testId -or $_.RowKey -eq $Block.testId } | Select-Object -First 1
                        if ($TestResult) {
                            if ($TestResult.TestType -eq 'Custom' -and $TestResult.ResultDataJson) {
                                try {
                                    $ParsedResult = ConvertFrom-Json -InputObject $TestResult.ResultDataJson
                                    # Apply markdown template if available
                                    if ($TestResult.MarkdownTemplate) {
                                        $Block.content = $TestResult.MarkdownTemplate
                                        # Note: Template resolution happens on the frontend; store raw for now
                                    }
                                } catch {
                                    # Fall back to ResultMarkdown
                                }
                            }
                            if (-not $Block.content -and $TestResult.ResultMarkdown) {
                                $Block | Add-Member -NotePropertyName 'content' -NotePropertyValue $TestResult.ResultMarkdown -Force
                            }
                        }
                    }
                    $Block
                })

            # Store the generated report with a GUID
            $ReportGUID = (New-Guid).GUID
            $ReportTable = Get-CippTable -tablename 'ReportBuilderReports'
            $ReportEntity = @{
                PartitionKey = $TenantFilter
                RowKey       = [string]$ReportGUID
                TemplateName = [string]$TemplateName
                TenantFilter = [string]$TenantFilter
                Blocks       = [string](ConvertTo-Json -InputObject @($EnrichedBlocks) -Depth 20 -Compress)
                GeneratedAt  = [string](Get-Date).ToString('o')
                Status       = 'Completed'
            }

            Add-CIPPAzDataTableEntity @ReportTable -Entity $ReportEntity -Force
            Write-LogMessage -headers $Headers -API $APIName -tenant $TenantFilter -message "Generated report builder report '$TemplateName' with GUID $ReportGUID" -Sev 'Info'

            $Result = @{
                Results    = "Successfully generated report '$TemplateName'"
                ReportGUID = $ReportGUID
                Blocks     = @($EnrichedBlocks)
            }
            $StatusCode = [HttpStatusCode]::OK

        } # end else (generate)
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Write-LogMessage -headers $Headers -API $APIName -message "Report generation error: $($ErrorMessage.NormalizedError)" -Sev 'Error' -LogData $ErrorMessage
        $Result = @{ Results = "Error: $($ErrorMessage.NormalizedError)" }
        $StatusCode = [HttpStatusCode]::BadRequest
    }

    return ([HttpResponseContext]@{
            StatusCode = $StatusCode
            Body       = ConvertTo-Json -InputObject $Result -Depth 20
        })
}
