function Invoke-ExecGetReportBuilderPdf {
    <#
    .FUNCTIONALITY
        Entrypoint,AnyTenant
    .ROLE
        CIPP.ReportBuilder.Read
    .DESCRIPTION
        Returns the server-rendered PDF for a generated Report Builder report as application/pdf bytes.
        Backs both the in-app preview (shown in an iframe) and the download button on the view page.
        404 when the report has no rendered PDF (generated before server-side rendering, or its render
        failed), and also when the report belongs to a tenant the caller cannot access.
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $APIName = $TriggerMetadata.FunctionName
    Write-LogMessage -Headers $Request.Headers -API $APIName -message 'Accessed this API' -Sev 'Debug'

    try {
        # The generated report's GUID.
        $ReportGUID = $Request.Query.id ?? $Request.Query.ReportGUID
        if ([string]::IsNullOrEmpty($ReportGUID)) {
            return ([HttpResponseContext]@{ StatusCode = [HttpStatusCode]::BadRequest; Body = 'A report id is required' })
        }
        $ReportGUID = ConvertTo-CIPPODataFilterValue -Value $ReportGUID -Type 'Guid'

        # The PDF lives in its own table (keyed by the report GUID) so listing reports never pulls the
        # base64. No -Property projection: the merge-aware read reassembles a PDF split across part rows.
        $Table = Get-CippTable -tablename 'ReportBuilderPdfs'
        $Row = Get-CIPPAzDataTableEntity @Table -Filter "RowKey eq '$ReportGUID'" | Select-Object -First 1
        if ([string]::IsNullOrEmpty($Row.Pdf)) {
            return ([HttpResponseContext]@{ StatusCode = [HttpStatusCode]::NotFound; Body = 'This report has no rendered PDF. Regenerate it to produce one.' })
        }

        # The request carries only the report id, so the framework has no tenant to check (AnyTenant).
        # The row is partitioned by the tenant it was generated for; a restricted caller only gets PDFs
        # of tenants they can access, and the same 404 otherwise so ids of other tenants' reports leak nothing.
        $AllowedTenants = Test-CIPPAccess -Request $Request -TenantList
        if ($AllowedTenants -notcontains 'AllTenants') {
            $AllowedDomains = @(Get-Tenants -IncludeErrors | Where-Object { $_.customerId -in $AllowedTenants } | ForEach-Object { [string]$_.defaultDomainName })
            if ([string]$Row.PartitionKey -notin $AllowedDomains) {
                return ([HttpResponseContext]@{ StatusCode = [HttpStatusCode]::NotFound; Body = 'This report has no rendered PDF. Regenerate it to produce one.' })
            }
        }

        return ([HttpResponseContext]@{
                StatusCode  = [HttpStatusCode]::OK
                ContentType = 'application/pdf'
                Headers     = @{ 'Content-Disposition' = "inline; filename=`"$($Row.FileName ?? "Report_$ReportGUID.pdf")`"" }
                Body        = [Convert]::FromBase64String($Row.Pdf)
            })
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Write-LogMessage -Headers $Request.Headers -API $APIName -message "Failed to fetch report PDF: $($ErrorMessage.NormalizedError)" -Sev 'Error' -LogData $ErrorMessage
        return ([HttpResponseContext]@{ StatusCode = [HttpStatusCode]::InternalServerError; Body = "Error: $($ErrorMessage.NormalizedError)" })
    }
}
