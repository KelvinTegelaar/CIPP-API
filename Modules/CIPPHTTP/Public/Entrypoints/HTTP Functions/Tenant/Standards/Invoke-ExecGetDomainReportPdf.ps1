function Invoke-ExecGetDomainReportPdf {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        Tenant.DomainAnalyser.Read
    .SYNOPSIS
        Domain security assessment PDF
    .DESCRIPTION
        Server-renders a client-facing domain security assessment (SPF, DKIM, DMARC, MX, DNSSEC, MTA-STS and the Intune
        enrolment records) covering every domain of one tenant as application/pdf bytes, from the stored Domain Analyser
        results. No DNS lookups are made; run the Domain Analyser to refresh the results first.
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $APIName = $TriggerMetadata.FunctionName
    $TenantFilter = $Request.Query.tenantFilter
    if ([string]::IsNullOrWhiteSpace($TenantFilter) -or $TenantFilter -eq 'AllTenants') {
        return ([HttpResponseContext]@{ StatusCode = [HttpStatusCode]::BadRequest; Body = 'Select a single tenant to report on' })
    }

    try {
        # Include the published records and every individual test result for each domain.
        $IncludeDetails = [string]$Request.Query.includeDetails -ne 'false'
        $BrandingPresetId = [string]$Request.Query.brandingPresetId

        $Tenant = @(Get-Tenants -TenantFilter $TenantFilter)[0]
        $DomainTable = Get-CIPPTable -tablename 'Domains'
        $Rows = @(if ($Tenant.customerId) { Get-CIPPAzDataTableEntity @DomainTable -Filter ("PartitionKey eq 'TenantDomains' and TenantGUID eq '{0}'" -f $Tenant.customerId) })
        if (-not @($Rows.Where({ $_.DomainAnalyser })).Count) {
            return ([HttpResponseContext]@{ StatusCode = [HttpStatusCode]::NotFound; Body = 'No Domain Analyser results for this tenant. Run the Domain Analyser first.' })
        }

        $TenantName = Get-CippReportTenantName -TenantFilter $TenantFilter -BrandingPresetId $BrandingPresetId
        $Report = Build-CippDomainReportTree -Data @{
            TenantName     = $TenantName
            IncludeDetails = $IncludeDetails
            Domains        = @(foreach ($Row in $Rows) {
                    @{
                        Domain        = $Row.RowKey
                        Result        = if ($Row.DomainAnalyser) { $Row.DomainAnalyser | ConvertFrom-Json }
                        Checks        = if ($Row.DomainAnalyserChecks) { $Row.DomainAnalyserChecks | ConvertFrom-Json }
                        DkimSelectors = if ($Row.DkimSelectors) { @($Row.DkimSelectors | ConvertFrom-Json) }
                    }
                })
        }
        $Bytes = ConvertTo-CippReportPdf -Blocks $Report.Blocks -Variables $Report.Variables -TenantName $TenantName -TenantFilter $TenantFilter -ReportName 'Domain Security Assessment' -BrandingPresetId $BrandingPresetId
        $FileName = ("Domain_Security_Assessment_$TenantFilter" -replace '[^a-zA-Z0-9_\-]', '_') + '.pdf'
        return ([HttpResponseContext]@{
                StatusCode  = [HttpStatusCode]::OK
                ContentType = 'application/pdf'
                Headers     = @{ 'Content-Disposition' = "inline; filename=`"$FileName`"" }
                Body        = $Bytes
            })
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Write-LogMessage -Headers $Request.Headers -API $APIName -tenant $TenantFilter -message "Failed to render the domain security report: $($ErrorMessage.NormalizedError)" -Sev 'Error' -LogData $ErrorMessage
        return ([HttpResponseContext]@{ StatusCode = Get-CippErrorStatusCode -ErrorRecord $_; Body = "Error: $($ErrorMessage.NormalizedError)" })
    }
}
