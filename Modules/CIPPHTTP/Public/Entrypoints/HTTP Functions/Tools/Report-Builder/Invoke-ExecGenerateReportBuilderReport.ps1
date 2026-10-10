function Invoke-ExecGenerateReportBuilderReport {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        CIPP.ReportBuilder.ReadWrite
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
                Remove-CIPPAzDataTableEntity @ReportTable -Entity $ExistingEntity
                # The rendered PDF sits in its own table; a large one is split across part rows, so fetch
                # the raw head + part rows (keys only, no split markers) and hand them all to the remover.
                $PdfTable = Get-CippTable -tablename 'ReportBuilderPdfs'
                $PdfRows = @(Get-CIPPAzDataTableEntity @PdfTable -Filter "RowKey eq '$($Body.ReportGUID)' or OriginalEntityId eq '$($Body.ReportGUID)'" -Property PartitionKey, RowKey)
                if ($PdfRows.Count -gt 0) { Remove-CIPPAzDataTableEntity @PdfTable -Entity $PdfRows }
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

            # Delegate to the scheduler-callable function
            $GenerateParams = @{
                TenantFilter = $TenantFilter
                TemplateName = $TemplateName
            }
            if ($Body.Blocks) {
                $GenerateParams.Blocks = if ($Body.Blocks -is [string]) { $Body.Blocks } else { ConvertTo-Json -InputObject @($Body.Blocks) -Depth 20 -Compress }
            }
            if ($Body.TemplateGUID) {
                $GenerateParams.TemplateGUID = $Body.TemplateGUID
            }

            $GenerateResult = Push-ExecGenerateReportBuilderReport @GenerateParams
            Write-LogMessage -headers $Headers -API $APIName -tenant $TenantFilter -message "Generated report builder report '$TemplateName'" -Sev 'Info'

            # Push-* returns either the plain result string, or an envelope carrying base64 email
            # attachments for the scheduled path. The interactive HTTP response only needs the message -
            # the finished PDF is fetched from ExecGetReportBuilderPdf, not echoed here as base64.
            $ResultText = if ($GenerateResult -is [System.Collections.IDictionary] -and $GenerateResult['Results']) { $GenerateResult['Results'] } else { $GenerateResult }
            $Result = @{
                Results = $ResultText
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
            Body       = $Result
        })
}
