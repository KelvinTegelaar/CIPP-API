function Invoke-ExecGetShadowAIReportPdf {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        Tenant.Standards.Read
    .DESCRIPTION
        Server-renders the Shadow AI report as application/pdf bytes. Gathers the same shaped data the
        Shadow AI page uses (ListShadowAI) and composes it through the shared CIPPSharp component kit
        (Build-CippShadowAIReportTree) - the server-side replacement for the client react-pdf
        ShadowAIReportButton.
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

        # Optional per-section toggles from the client's section panel (POST body). Absent -> full report.
        $SectionConfig = @{}
        $RawCfg = $Request.Body.sectionConfig
        if ($RawCfg -is [hashtable]) { $SectionConfig = $RawCfg }
        elseif ($RawCfg) { foreach ($p in $RawCfg.PSObject.Properties) { $SectionConfig[$p.Name] = [bool]$p.Value } }

        # The same shaped data the Shadow AI page reads (from the reporting cache).
        $Raw = Get-CIPPShadowAIReport -TenantFilter $TenantFilter
        $Report = Build-CippShadowAIReportTree -SectionConfig $SectionConfig -Data @{
            TenantName    = $TenantName
            summary       = $Raw.summary
            detectedApps  = $Raw.detectedApps
            consentedApps = $Raw.consentedApps
            topTools      = $Raw.topTools
            byRisk        = $Raw.byRisk
        }

        $Bytes = ConvertTo-CippReportPdf -Blocks $Report.Blocks -Variables $Report.Variables -TenantName $TenantName -TenantFilter $TenantFilter -ReportName 'Shadow AI Report'
        $FileName = ("Shadow_AI_Report_$TenantFilter" -replace '[^a-zA-Z0-9_\-]', '_') + '.pdf'
        return ([HttpResponseContext]@{
                StatusCode  = [HttpStatusCode]::OK
                ContentType = 'application/pdf'
                Headers     = @{ 'Content-Disposition' = "inline; filename=`"$FileName`"" }
                Body        = $Bytes
            })
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Write-LogMessage -Headers $Request.Headers -API $APIName -message "Failed to render Shadow AI report: $($ErrorMessage.NormalizedError)" -Sev 'Error' -LogData $ErrorMessage
        return ([HttpResponseContext]@{ StatusCode = [HttpStatusCode]::InternalServerError; Body = "Error: $($ErrorMessage.NormalizedError)" })
    }
}
