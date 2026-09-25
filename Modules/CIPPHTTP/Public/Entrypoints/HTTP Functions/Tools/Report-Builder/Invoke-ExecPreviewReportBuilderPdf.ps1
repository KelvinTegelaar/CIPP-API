function Invoke-ExecPreviewReportBuilderPdf {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        CIPP.ReportBuilder.ReadWrite
    .DESCRIPTION
        Renders the current (unsaved) Report Builder state to a PDF and returns it as application/pdf
        bytes without persisting a generated-report row. Powers the builder's live preview and download.
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $APIName = $TriggerMetadata.FunctionName
    $Headers = $Request.Headers

    try {
        $Body = $Request.Body
        $TenantFilter = $Body.TenantFilter ?? $Request.Query.TenantFilter
        if ([string]::IsNullOrEmpty($TenantFilter)) { throw 'TenantFilter is required' }

        $GenerateParams = @{
            TenantFilter = $TenantFilter
            TemplateName = $Body.TemplateName ?? 'Report'
            PreviewOnly  = $true
        }
        if ($Body.Blocks) {
            $GenerateParams.Blocks = if ($Body.Blocks -is [string]) { $Body.Blocks } else { ConvertTo-Json -InputObject @($Body.Blocks) -Depth 20 -Compress }
        }
        if ($Body.TemplateGUID) { $GenerateParams.TemplateGUID = $Body.TemplateGUID }
        if ($Body.Settings) {
            $GenerateParams.Settings = if ($Body.Settings -is [string]) { $Body.Settings } else { ConvertTo-Json -InputObject $Body.Settings -Depth 10 -Compress }
        }

        $Preview = Push-ExecGenerateReportBuilderReport @GenerateParams

        if (-not $Preview.PdfBytes) {
            return ([HttpResponseContext]@{
                    StatusCode = [HttpStatusCode]::InternalServerError
                    Body       = 'Failed to render the report preview.'
                })
        }

        return ([HttpResponseContext]@{
                StatusCode  = [HttpStatusCode]::OK
                ContentType = 'application/pdf'
                Body        = $Preview.PdfBytes
            })
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Write-LogMessage -headers $Headers -API $APIName -message "Report preview error: $($ErrorMessage.NormalizedError)" -Sev 'Error' -LogData $ErrorMessage
        return ([HttpResponseContext]@{
                StatusCode = [HttpStatusCode]::InternalServerError
                Body       = "Error: $($ErrorMessage.NormalizedError)"
            })
    }
}
