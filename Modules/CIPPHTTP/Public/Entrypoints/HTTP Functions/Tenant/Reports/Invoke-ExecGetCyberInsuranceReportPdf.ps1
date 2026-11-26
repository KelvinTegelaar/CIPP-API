function Invoke-ExecGetCyberInsuranceReportPdf {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        Tenant.Reports.Read
    .SYNOPSIS
        Download the Cyber Insurance Readiness report as a PDF
    .DESCRIPTION
        Renders the Cyber Insurance Readiness report for one tenant as a PDF: a summary, the 25 application questions in order, the detail behind each answer read from the tenant, the questions the MSP attests to, and a scope and limitations statement.
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $TenantFilter = $Request.Query.tenantFilter
    if (-not $TenantFilter -or $TenantFilter -eq 'AllTenants') {
        return ([HttpResponseContext]@{ StatusCode = [HttpStatusCode]::BadRequest; Body = 'The cyber insurance report runs against a single tenant' })
    }

    try {
        $TenantName = Get-CippReportTenantName -TenantFilter $TenantFilter -BrandingPresetId ''
        $Report = Get-CIPPCyberInsuranceReport -TenantFilter $TenantFilter
        $Tree = Build-CippCyberInsuranceReportTree -Data @{ TenantName = $TenantName; summary = $Report.summary; questions = $Report.questions }

        $Bytes = ConvertTo-CippReportPdf -Blocks $Tree.Blocks -Variables $Tree.Variables -TenantName $TenantName -TenantFilter $TenantFilter -ReportName 'Cyber Insurance Readiness Report'
        $FileName = ("Cyber_Insurance_Report_$TenantFilter" -replace '[^a-zA-Z0-9_\-]', '_') + '.pdf'
        return ([HttpResponseContext]@{
                StatusCode  = [HttpStatusCode]::OK
                ContentType = 'application/pdf'
                Headers     = @{ 'Content-Disposition' = "inline; filename=`"$FileName`"" }
                Body        = $Bytes
            })
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Write-LogMessage -Headers $Request.Headers -API $TriggerMetadata.FunctionName -tenant $TenantFilter -message "Failed to render the cyber insurance report: $($ErrorMessage.NormalizedError)" -Sev 'Error' -LogData $ErrorMessage
        return ([HttpResponseContext]@{ StatusCode = [HttpStatusCode]::InternalServerError; Body = "Error: $($ErrorMessage.NormalizedError)" })
    }
}
