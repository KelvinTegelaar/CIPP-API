function Invoke-ExecGetSharingReportPdf {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        Sharepoint.Site.Read
    .DESCRIPTION
        Server-renders the SharePoint & OneDrive Sharing report as application/pdf bytes. Gathers the same
        shaped data the Sharing page uses (ListSharePointSharing, from the CIPP reporting cache), composes
        it through the shared CIPPSharp component kit (Build-CippSharingReportTree) and returns the finished
        PDF - the server-side replacement for the client react-pdf SharingReportButton.
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

        # The same shaped data the Sharing page reads (from the reporting cache; no live Graph enumeration).
        $Raw = Get-CIPPSharePointSharingReport -TenantFilter $TenantFilter
        $Report = Build-CippSharingReportTree -Data @{
            TenantName    = $TenantName
            summary       = $Raw.summary
            links         = $Raw.links
            topRecipients = $Raw.topRecipients
            topLibraries  = $Raw.topLibraries
        }

        $Bytes = ConvertTo-CippReportPdf -Blocks $Report.Blocks -Variables $Report.Variables -TenantName $TenantName -TenantFilter $TenantFilter -ReportName 'Sharing Report'
        $FileName = ("Sharing_Report_$TenantFilter" -replace '[^a-zA-Z0-9_\-]', '_') + '.pdf'
        return ([HttpResponseContext]@{
                StatusCode  = [HttpStatusCode]::OK
                ContentType = 'application/pdf'
                Headers     = @{ 'Content-Disposition' = "inline; filename=`"$FileName`"" }
                Body        = $Bytes
            })
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Write-LogMessage -Headers $Request.Headers -API $APIName -message "Failed to render Sharing report: $($ErrorMessage.NormalizedError)" -Sev 'Error' -LogData $ErrorMessage
        return ([HttpResponseContext]@{ StatusCode = [HttpStatusCode]::InternalServerError; Body = "Error: $($ErrorMessage.NormalizedError)" })
    }
}
