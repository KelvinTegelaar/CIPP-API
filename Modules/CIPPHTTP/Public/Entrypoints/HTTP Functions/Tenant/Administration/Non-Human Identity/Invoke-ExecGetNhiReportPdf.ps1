function Invoke-ExecGetNhiReportPdf {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        Tenant.Application.Read
    .SYNOPSIS
        Renders a non-human identity (NHI) compromise case as a PDF report.
    .DESCRIPTION
        Server-renders a completed NHI run as application/pdf bytes: the case level, what was found, priority actions, order of events, containment already run, and the addresses, credentials, changes, mail and file reach, access and owners behind it. Reads the stored run; it does not start an investigation. The app in other tenants is never included. Metadata only.
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $APIName = $Request.Params.CIPPEndpoint
    $TenantFilter = $Request.Query.tenantFilter ?? $Request.Body.tenantFilter
    # The completed run to render
    $CaseId = [string]($Request.Query.caseId ?? $Request.Body.caseId)
    # The branding preset to render with; omitted -> the default branding
    $BrandingPresetId = [string]($Request.Query.brandingPresetId ?? $Request.Body.brandingPresetId)

    if (-not $TenantFilter -or -not $CaseId) {
        return ([HttpResponseContext]@{ StatusCode = [HttpStatusCode]::BadRequest; Body = 'A tenantFilter and a caseId are required' })
    }

    try {
        $Run = Get-CIPPBecReport -Kind 'NHI' -TenantFilter $TenantFilter -CaseId $CaseId -IncludeResults -ErrorAction Stop
        if (-not $Run -or $Run.Status -ne 'Completed' -or -not $Run.Results) {
            throw [System.Management.Automation.ItemNotFoundException]::new("No completed NHI investigation is stored for case '$CaseId'. Wait for the investigation to finish, then generate the report.")
        }
        $TenantName = Get-CippReportTenantName -TenantFilter $TenantFilter -BrandingPresetId $BrandingPresetId
        $Report = Build-CippNhiReportTree -NhiData $Run.Results -Containment @($Run.Containment) -TenantName $TenantName
        $Bytes = ConvertTo-CippReportPdf -Blocks $Report.Blocks -Variables $Report.Variables -TenantName $TenantName -TenantFilter $TenantFilter -ReportName 'NHI Compromise Report' -BrandingPresetId $BrandingPresetId
        $FileName = ("NHI_Report_$($Run.Results.DisplayName)" -replace '[^a-zA-Z0-9_\-]', '_') + '.pdf'
        return ([HttpResponseContext]@{
                StatusCode  = [HttpStatusCode]::OK
                ContentType = 'application/pdf'
                Headers     = @{ 'Content-Disposition' = "inline; filename=`"$FileName`"" }
                Body        = $Bytes
            })
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        $StatusCode = Get-CippErrorStatusCode -ErrorRecord $_
        if ($StatusCode -eq [HttpStatusCode]::InternalServerError) {
            Write-LogMessage -headers $Request.Headers -API $APIName -tenant $TenantFilter -message "Failed to render the NHI report for case $($CaseId): $($ErrorMessage.NormalizedError)" -Sev 'Error' -LogData $ErrorMessage
        }
        return ([HttpResponseContext]@{ StatusCode = $StatusCode; Body = $ErrorMessage.NormalizedError })
    }
}
