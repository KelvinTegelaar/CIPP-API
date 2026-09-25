function Invoke-ExecGetLicenseReportPdf {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        Tenant.Directory.Read
    .DESCRIPTION
        Server-renders the License Optimisation report as application/pdf bytes. Runs the same license
        recommendation analysis the License Optimization page reads through ListLicenseRecommendations
        (Get-CIPPLicenseRecommendation, with the page's currency, thresholds and recommendation switches)
        and composes it through the shared CIPPSharp kit (Build-CippLicenseReportTree) - the server-side
        replacement for the client react-pdf LicenseReportButton.
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $APIName = $TriggerMetadata.FunctionName
    Write-LogMessage -Headers $Request.Headers -API $APIName -message 'Accessed this API' -Sev 'Debug'

    # The tenant to report on. A single tenant; AllTenants is not supported.
    $TenantFilter = $Request.Query.tenantFilter ?? $Request.Body.tenantFilter
    if ([string]::IsNullOrWhiteSpace($TenantFilter) -or $TenantFilter -eq 'AllTenants') {
        return ([HttpResponseContext]@{ StatusCode = [HttpStatusCode]::BadRequest; Body = 'A single tenant is required for the license report.' })
    }
    # Currency the money figures are resolved in: a three-letter ISO code such as USD or EUR. Defaults to USD.
    $Currency = [string]($Request.Body.currency ?? $Request.Query.currency ?? 'USD')
    if ($Currency -notmatch '^[A-Za-z]{3}$') {
        return ([HttpResponseContext]@{ StatusCode = [HttpStatusCode]::BadRequest; Body = 'currency must be a three-letter ISO currency code.' })
    }
    $Currency = $Currency.ToUpperInvariant()
    # Days without a sign-in after which a licensed person counts as inactive (1-365). Defaults to 90.
    $InactiveDays = ($Request.Body.inactiveDays ?? $Request.Query.inactiveDays ?? 90) -as [int]
    if ($InactiveDays -lt 1 -or $InactiveDays -gt 365) {
        return ([HttpResponseContext]@{ StatusCode = [HttpStatusCode]::BadRequest; Body = 'inactiveDays must be a whole number from 1 to 365.' })
    }
    # Months a seat must have been held by the same person to count as stable for a yearly commitment (1-36). Defaults to 6.
    $TenureMonths = ($Request.Body.tenureMonths ?? $Request.Query.tenureMonths ?? 6) -as [int]
    if ($TenureMonths -lt 1 -or $TenureMonths -gt 36) {
        return ([HttpResponseContext]@{ StatusCode = [HttpStatusCode]::BadRequest; Body = 'tenureMonths must be a whole number from 1 to 36.' })
    }

    # The recommendation switches, read exactly as ListLicenseRecommendations reads them so the PDF agrees
    # with the page: missing is on, and only false/0/no/off turns a switch off.
    $AsBool = {
        param($Value, $Default)
        if ($null -eq $Value -or [string]::IsNullOrWhiteSpace([string]$Value)) { return $Default }
        return ([string]$Value) -notin @('false', '0', 'no', 'off')
    }
    $RecommendDowngrades = & $AsBool ($Request.Body.recommendDowngrades ?? $Request.Query.recommendDowngrades) $true
    $RecommendUpgrades = & $AsBool ($Request.Body.recommendUpgrades ?? $Request.Query.recommendUpgrades) $true
    $RecommendTerms = & $AsBool ($Request.Body.recommendTerms ?? $Request.Query.recommendTerms) $true
    $ProtectSecurityFeatures = & $AsBool ($Request.Body.protectSecurityFeatures ?? $Request.Query.protectSecurityFeatures) $true

    # Report pages to include. Each defaults to on; only an explicit false drops that page. The summary
    # page is always included.
    $Sections = @{
        spend      = $Request.Body.sections.spend -ne $false
        reclaim    = $Request.Body.sections.reclaim -ne $false
        downgrades = $Request.Body.sections.downgrades -ne $false
        upgrades   = $Request.Body.sections.upgrades -ne $false
        terms      = $Request.Body.sections.terms -ne $false
        method     = $Request.Body.sections.method -ne $false
    }
    # The branding preset to render against (the Licensing Report default from the branding settings),
    # else the global branding.
    $BrandingPresetId = [string]($Request.Body.brandingPresetId ?? $Request.Query.brandingPresetId)

    try {
        $TenantName = Get-CippReportTenantName -TenantFilter $TenantFilter -BrandingPresetId $BrandingPresetId
        $Report = Get-CIPPLicenseRecommendation -TenantFilter $TenantFilter -Currency $Currency -InactiveDays $InactiveDays -TenureMonths $TenureMonths `
            -RecommendDowngrades $RecommendDowngrades -RecommendUpgrades $RecommendUpgrades -RecommendTerms $RecommendTerms -ProtectSecurityFeatures $ProtectSecurityFeatures
        $Data = @{ TenantName = $TenantName }
        foreach ($Property in $Report.PSObject.Properties) { $Data[$Property.Name] = $Property.Value }

        # Both date the report today in the instance's timezone.
        $Tree = Build-CippLicenseReportTree -Data $Data -Sections $Sections
        $Bytes = ConvertTo-CippReportPdf -Blocks $Tree.Blocks -Variables $Tree.Variables -TenantName $TenantName -TenantFilter $TenantFilter `
            -ReportName 'Licensing Report' -BrandingPresetId $BrandingPresetId
        $FileName = ("Licensing_Report_$TenantFilter" -replace '[^a-zA-Z0-9_\-]', '_') + '.pdf'
        return ([HttpResponseContext]@{
                StatusCode  = [HttpStatusCode]::OK
                ContentType = 'application/pdf'
                Headers     = @{ 'Content-Disposition' = "inline; filename=`"$FileName`"" }
                Body        = $Bytes
            })
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Write-LogMessage -Headers $Request.Headers -API $APIName -tenant $TenantFilter -message "Failed to render Licensing report: $($ErrorMessage.NormalizedError)" -Sev 'Error' -LogData $ErrorMessage
        return ([HttpResponseContext]@{ StatusCode = [HttpStatusCode]::InternalServerError; Body = "Error: $($ErrorMessage.NormalizedError)" })
    }
}
