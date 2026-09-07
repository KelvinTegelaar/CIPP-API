function Get-CIPPLicensePrice {
    <#
    .SYNOPSIS
        Resolve the monthly price for one or all license SKUs, in a given currency.

    .DESCRIPTION
        Merges the shipped MSRP estimate list (Config\LicensePricingDefaults.csv) with the
        MSP-maintained override table (LicensePricing). An override always wins over the estimate.
        Both are multi-currency: each SKU can have a row per ISO currency. Prices are MSP-global
        (not per-tenant).

        Returns one price object per SKU for the requested -Currency, with a Source of:
        - 'Override' : an explicit price the MSP entered for this currency
        - 'Estimate' : the shipped public MSRP fallback for this currency (subject to drift)
        - 'Unknown'  : the SKU has no price in the requested currency (MonthlyPrice is $null)

        There is no cross-currency conversion: asking for AUD returns only AUD prices. A single
        -SkuId lookup with no price in the requested currency is reported 'Unknown' (null price); the
        full list (the price matrix) omits such SKUs entirely rather than showing empty rows.

    .PARAMETER SkuId
        Optional. Return the single resolved price object for this SKU GUID. Omit to return every
        known SKU (overrides merged over estimates) for the requested currency.

    .PARAMETER Currency
        ISO currency code to resolve prices in. Defaults to USD.

    .PARAMETER ListCurrencies
        Return the sorted list of currency codes present in the estimates + overrides instead of
        prices. Used to populate the currency selector.

    .FUNCTIONALITY
        Internal
    #>
    [CmdletBinding()]
    param(
        [string]$SkuId,
        [string]$Currency = 'USD',
        [switch]$ListCurrencies
    )

    # currency (lower) -> @{ skuId (lower) -> price object }
    $Estimate = @{}
    $Override = @{}
    # skuId (lower) -> metadata shared across currencies (name / part number)
    $SkuMeta = @{}
    $CurrencySet = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)

    # Shipped MSRP estimates (public list prices, subject to drift - labelled Estimate)
    try {
        $CsvPath = Join-Path $env:CIPPRootPath 'Config\LicensePricingDefaults.csv'
        if (Test-Path $CsvPath) {
            foreach ($Row in (Import-Csv -Path $CsvPath)) {
                $Key = ([string]$Row.skuId).ToLowerInvariant()
                if ([string]::IsNullOrWhiteSpace($Key)) { continue }
                $Cur = if ($Row.Currency) { [string]$Row.Currency } else { 'USD' }
                $null = $CurrencySet.Add($Cur)
                $CurKey = $Cur.ToLowerInvariant()
                if (-not $Estimate.ContainsKey($CurKey)) { $Estimate[$CurKey] = @{} }
                $Estimate[$CurKey][$Key] = [pscustomobject]@{
                    skuId                = $Key
                    skuPartNumber        = [string]$Row.skuPartNumber
                    Product_Display_Name = [string]$Row.Product_Display_Name
                    MonthlyPrice         = [double]$Row.MonthlyPrice
                    Currency             = $Cur
                    Source               = 'Estimate'
                }
                if (-not $SkuMeta.ContainsKey($Key)) {
                    $SkuMeta[$Key] = [pscustomobject]@{ skuPartNumber = [string]$Row.skuPartNumber; Product_Display_Name = [string]$Row.Product_Display_Name }
                }
            }
        }
    } catch {
        Write-Information "Get-CIPPLicensePrice: failed to read defaults CSV: $($_.Exception.Message)"
    }

    # MSP overrides (win over estimates, per currency)
    try {
        $Table = Get-CIPPTable -TableName 'LicensePricing'
        foreach ($Row in (Get-CIPPAzDataTableEntity @Table)) {
            $Key = if ($Row.skuId) { ([string]$Row.skuId).ToLowerInvariant() } else { (([string]$Row.RowKey) -split '-')[0].ToLowerInvariant() }
            if ([string]::IsNullOrWhiteSpace($Key)) { continue }
            $Cur = if ($Row.Currency) { [string]$Row.Currency } else { 'USD' }
            $null = $CurrencySet.Add($Cur)
            $CurKey = $Cur.ToLowerInvariant()
            if (-not $Override.ContainsKey($CurKey)) { $Override[$CurKey] = @{} }
            $Override[$CurKey][$Key] = [pscustomobject]@{
                skuId                = $Key
                skuPartNumber        = [string]$Row.skuPartNumber
                Product_Display_Name = [string]$Row.Product_Display_Name
                MonthlyPrice         = [double]$Row.MonthlyPrice
                Currency             = $Cur
                Source               = 'Override'
            }
            if (-not $SkuMeta.ContainsKey($Key)) {
                $SkuMeta[$Key] = [pscustomobject]@{ skuPartNumber = [string]$Row.skuPartNumber; Product_Display_Name = [string]$Row.Product_Display_Name }
            }
        }
    } catch {
        Write-Information "Get-CIPPLicensePrice: failed to read override table: $($_.Exception.Message)"
    }

    if ($ListCurrencies) {
        return @($CurrencySet | Sort-Object)
    }

    $WantCur = $Currency.ToLowerInvariant()
    $ResolveOne = {
        param($Sku)
        if ($Override.ContainsKey($WantCur) -and $Override[$WantCur].ContainsKey($Sku)) { return $Override[$WantCur][$Sku] }
        if ($Estimate.ContainsKey($WantCur) -and $Estimate[$WantCur].ContainsKey($Sku)) { return $Estimate[$WantCur][$Sku] }
        $Meta = $SkuMeta[$Sku]
        return [pscustomobject]@{
            skuId                = $Sku
            skuPartNumber        = if ($Meta) { $Meta.skuPartNumber } else { $null }
            Product_Display_Name = if ($Meta) { $Meta.Product_Display_Name } else { $null }
            MonthlyPrice         = $null
            Currency             = $Currency
            Source               = 'Unknown'
        }
    }

    if ($SkuId) {
        return & $ResolveOne ([string]$SkuId).ToLowerInvariant()
    }

    # The full list is the price matrix: only SKUs that actually carry a price in this currency
    # (a SKU priced in USD but not the requested currency is omitted, not shown as 'Unknown').
    $Result = foreach ($Sku in $SkuMeta.Keys) { & $ResolveOne $Sku }
    return @($Result | Where-Object { $null -ne $_.MonthlyPrice } | Sort-Object -Property Product_Display_Name)
}
