function Invoke-ExecGetPermissionsReportPdf {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        Sharepoint.Site.Read
    .DESCRIPTION
        Server-renders the SharePoint Permissions report as application/pdf bytes. Gathers the same shaped
        data the Permissions page uses (ListSharePointPermissions, from the CIPP reporting cache), composes
        it through the shared CIPPSharp component kit (Build-CippPermissionsReportTree) and returns the
        finished PDF - the server-side replacement for the client react-pdf PermissionsReportButton.
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $APIName = $TriggerMetadata.FunctionName
    Write-LogMessage -Headers $Request.Headers -API $APIName -message 'Accessed this API' -Sev 'Debug'

    try {
        $TenantFilter = $Request.Query.tenantFilter ?? $Request.Body.tenantFilter
        if ([string]::IsNullOrWhiteSpace($TenantFilter)) {
            return ([HttpResponseContext]@{ StatusCode = [HttpStatusCode]::BadRequest; Body = 'A tenantFilter is required' })
        }
        $TenantName = Get-CippReportTenantName -TenantFilter $TenantFilter

        # The same shaped data the Permissions page reads (from the reporting cache).
        $Raw = Get-CIPPSharePointPermissionsReport -TenantFilter $TenantFilter
        $Report = Build-CippPermissionsReportTree -Data @{
            TenantName   = $TenantName
            summary      = $Raw.summary
            assignments  = $Raw.assignments
            skippedSites = $Raw.skippedSites
        }

        $Bytes = ConvertTo-CippReportPdf -Blocks $Report.Blocks -Variables $Report.Variables -TenantName $TenantName -TenantFilter $TenantFilter -ReportName 'Permissions Report'
        $FileName = ("Permissions_Report_$TenantFilter" -replace '[^a-zA-Z0-9_\-]', '_') + '.pdf'
        return ([HttpResponseContext]@{
                StatusCode  = [HttpStatusCode]::OK
                ContentType = 'application/pdf'
                Headers     = @{ 'Content-Disposition' = "inline; filename=`"$FileName`"" }
                Body        = $Bytes
            })
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Write-LogMessage -Headers $Request.Headers -API $APIName -message "Failed to render Permissions report: $($ErrorMessage.NormalizedError)" -Sev 'Error' -LogData $ErrorMessage
        return ([HttpResponseContext]@{ StatusCode = [HttpStatusCode]::InternalServerError; Body = "Error: $($ErrorMessage.NormalizedError)" })
    }
}
