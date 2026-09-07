function Invoke-ListLicensePricing {
    <#
    .FUNCTIONALITY
        Entrypoint,AnyTenant
    .ROLE
        Tenant.Directory.Read
    .DESCRIPTION
        Lists the resolved monthly price for every known license SKU: MSP price overrides merged
        over the shipped MSRP estimates. Consumed by the license optimization report and its
        price-management UI. Each row carries a Source of Override, Estimate, or Unknown.

        Prices are resolved in the requested currency (?currency=, default USD). The response also
        carries the list of currencies present in the price data so the UI can offer a selector.
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $APIName = $Request.Params.CIPPEndpoint
    $Headers = $Request.Headers

    # Currency to resolve prices in (ISO code); defaults to USD
    $Currency = $Request.Query.currency ?? $Request.Body.currency
    if ([string]::IsNullOrWhiteSpace($Currency)) { $Currency = 'USD' }

    try {
        $Results = @(Get-CIPPLicensePrice -Currency $Currency)
        $Currencies = @(Get-CIPPLicensePrice -ListCurrencies)
        $StatusCode = [HttpStatusCode]::OK
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        $StatusCode = [HttpStatusCode]::InternalServerError
        $Results = "Failed to list license pricing. $($ErrorMessage.NormalizedError)"
        $Currencies = @('USD')
        Write-LogMessage -API $APIName -headers $Headers -message $Results -Sev 'Error' -LogData $ErrorMessage
    }

    return ([HttpResponseContext]@{
            StatusCode = $StatusCode
            Body       = [pscustomobject]@{ 'Results' = $Results; 'Currencies' = $Currencies; 'Currency' = $Currency }
        })
}
