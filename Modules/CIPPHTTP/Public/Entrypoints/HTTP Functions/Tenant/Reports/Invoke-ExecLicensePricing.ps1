function Invoke-ExecLicensePricing {
    <#
    .FUNCTIONALITY
        Entrypoint,AnyTenant
    .ROLE
        Tenant.Directory.ReadWrite
    .DESCRIPTION
        Manage MSP-global license price overrides used by the license optimization report.
        SetPrice upserts a per-SKU monthly price; RemovePrice deletes an override so the SKU falls
        back to the shipped MSRP estimate.
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $APIName = $Request.Params.CIPPEndpoint
    $Headers = $Request.Headers
    $Table = Get-CIPPTable -TableName 'LicensePricing'

    try {
        # SetPrice or RemovePrice
        $Action = $Request.Body.Action
        if ([string]::IsNullOrWhiteSpace($Action)) { throw 'Action is required.' }
        # The SKU GUID (skuId) the price applies to
        $SkuId = ([string]$Request.Body.skuId).ToLowerInvariant()
        if ([string]::IsNullOrWhiteSpace($SkuId)) { throw 'skuId is required.' }

        # Overrides are currency-scoped: one row per (skuId, currency), so an AUD override and a
        # USD override for the same SKU coexist. RowKey = "{skuId}-{currency}".
        $Currency = if ($Request.Body.Currency) { [string]$Request.Body.Currency } else { 'USD' }
        $RowKey = '{0}-{1}' -f $SkuId, $Currency.ToLowerInvariant()

        switch ($Action) {
            'SetPrice' {
                # Monthly price per seat, in the given currency
                $MonthlyPrice = $Request.Body.MonthlyPrice -as [double]
                if ($null -eq $MonthlyPrice) { throw 'MonthlyPrice must be a number.' }

                $Entity = @{
                    PartitionKey           = 'Price'
                    RowKey                 = $RowKey
                    'skuId'                = $SkuId
                    'skuPartNumber'        = [string]$Request.Body.skuPartNumber
                    'Product_Display_Name' = [string]$Request.Body.Product_Display_Name
                    'MonthlyPrice'         = [double]$MonthlyPrice
                    'Currency'             = $Currency
                }
                Add-CIPPAzDataTableEntity @Table -Entity $Entity -Force
                $Result = "Success. Set price for $SkuId to $Currency $MonthlyPrice per month."
                Write-LogMessage -API $APIName -headers $Headers -message $Result -Sev 'Info'
            }
            'RemovePrice' {
                $Filter = "PartitionKey eq 'Price' and RowKey eq '{0}'" -f $RowKey
                $Entity = Get-CIPPAzDataTableEntity @Table -Filter $Filter -Property PartitionKey, RowKey
                if ($Entity) {
                    Remove-CIPPAzDataTableEntity -Force @Table -Entity $Entity
                }
                $Result = "Success. Removed the $Currency price override for $SkuId. It will fall back to the shipped estimate."
                Write-LogMessage -API $APIName -headers $Headers -message $Result -Sev 'Info'
            }
            default {
                $StatusCode = [HttpStatusCode]::BadRequest
                $Result = "Invalid action specified: $Action"
            }
        }
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        $StatusCode = [HttpStatusCode]::InternalServerError
        $Result = "Failed to update license pricing. $($ErrorMessage.NormalizedError)"
        Write-LogMessage -API $APIName -headers $Headers -message $Result -Sev 'Error' -LogData $ErrorMessage
    }

    return ([HttpResponseContext]@{
            StatusCode = $StatusCode ?? [HttpStatusCode]::OK
            Body       = [pscustomobject]@{ 'Results' = $Result }
        })
}
