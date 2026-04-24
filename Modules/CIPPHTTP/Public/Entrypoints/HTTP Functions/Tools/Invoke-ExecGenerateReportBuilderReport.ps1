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

            $Result = @{
                Results = $GenerateResult
            }
            $StatusCode = [HttpStatusCode]::OK

        } # end else (generate)
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Write-LogMessage -headers $Headers -API $APIName -message "Report generation error: $($ErrorMessage.NormalizedError)" -Sev 'Error' -LogData $ErrorMessage
        $Result = @{ Results = "Error: $($ErrorMessage.NormalizedError)" }
        $StatusCode = [HttpStatusCode]::BadRequest
    }

    Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
            StatusCode = $StatusCode
            Body       = ConvertTo-Json -InputObject $Result -Depth 20
        })
}
