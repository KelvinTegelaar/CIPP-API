function Invoke-ListLicenseRecommendations {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        Tenant.Directory.Read
    .DESCRIPTION
        License recommendation report for a tenant: the waste tiers from ListLicenseOptimization
        plus evidence-based downgrade targets (from 90-day usage reports against the license
        catalog), consolidation and protection upgrades, and the recommended annual/monthly
        commitment split per SKU. Feeds the License Optimization page and the client PDF.
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $APIName = $Request.Params.CIPPEndpoint
    $Headers = $Request.Headers

    # The tenant to report on
    $TenantFilter = $Request.Query.tenantFilter ?? $Request.Body.tenantFilter
    # Currency the money figures are resolved in (ISO code); defaults to USD
    $Currency = $Request.Query.currency ?? $Request.Body.currency
    if ([string]::IsNullOrWhiteSpace($Currency)) { $Currency = 'USD' }
    # Sign-in / activity age in days past which a user counts as inactive (default 90)
    $InactiveDays = ($Request.Query.inactiveDays ?? $Request.Body.inactiveDays) -as [int]
    if (-not $InactiveDays -or $InactiveDays -le 0) { $InactiveDays = 90 }
    # Months a seat must have been assigned to count as stable for an annual commitment (default 6)
    $TenureMonths = ($Request.Query.tenureMonths ?? $Request.Body.tenureMonths) -as [int]
    if (-not $TenureMonths -or $TenureMonths -le 0) { $TenureMonths = 6 }

    # Boolean switches arrive as strings on the query string; anything but an explicit false is on
    $AsBool = {
        param($Value, $Default)
        if ($null -eq $Value -or [string]::IsNullOrWhiteSpace([string]$Value)) { return $Default }
        return ([string]$Value) -notin @('false', '0', 'no', 'off')
    }
    $RecommendDowngrades = & $AsBool ($Request.Query.recommendDowngrades ?? $Request.Body.recommendDowngrades) $true
    $RecommendUpgrades = & $AsBool ($Request.Query.recommendUpgrades ?? $Request.Body.recommendUpgrades) $true
    $RecommendTerms = & $AsBool ($Request.Query.recommendTerms ?? $Request.Body.recommendTerms) $true
    $ProtectSecurityFeatures = & $AsBool ($Request.Query.protectSecurityFeatures ?? $Request.Body.protectSecurityFeatures) $true

    try {
        if ([string]::IsNullOrWhiteSpace($TenantFilter) -or $TenantFilter -eq 'AllTenants') { throw 'A single tenant is required for the license recommendation report.' }
        $Results = Get-CIPPLicenseRecommendation -TenantFilter $TenantFilter -Currency $Currency -InactiveDays $InactiveDays -TenureMonths $TenureMonths `
            -RecommendDowngrades $RecommendDowngrades -RecommendUpgrades $RecommendUpgrades -RecommendTerms $RecommendTerms -ProtectSecurityFeatures $ProtectSecurityFeatures
        $StatusCode = [System.Net.HttpStatusCode]::OK
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        $StatusCode = [System.Net.HttpStatusCode]::InternalServerError
        $Results = "Failed to build license recommendation report. $($ErrorMessage.NormalizedError)"
        Write-LogMessage -API $APIName -headers $Headers -tenant $TenantFilter -message $Results -Sev 'Error' -LogData $ErrorMessage
    }

    return ([HttpResponseContext]@{
            StatusCode = $StatusCode
            Body       = [pscustomobject]@{ 'Results' = $Results }
        })
}
