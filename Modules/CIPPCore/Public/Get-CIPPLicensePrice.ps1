function Get-CIPPLicensePrice {
    <#
    .SYNOPSIS
        Resolve the monthly price for one or all license SKUs, in a given currency.

    .DESCRIPTION
        Merges the shipped list-price catalog (Config\LicenseCatalog.json, see
        Get-CIPPLicenseCatalog) with the MSP-maintained override table (LicensePricing). An override
        always wins over the estimate. Both are multi-currency: each SKU can carry a price per ISO
        currency. Prices are MSP-global (not per-tenant).

        Returns one price object per SKU for the requested -Currency, with a Source of:
        - 'Override' : an explicit price the MSP entered for this currency
        - 'Estimate' : the shipped public list price for this currency (subject to drift)
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

    .PARAMETER IncludeUnknown
        In the full list, also return every SKU in the shipped SKU list (Config\ConversionTable.csv)
        that has no price in the requested currency (Source 'Unknown', null price), so the
        price-management page shows every SKU and each can be priced.

    .PARAMETER FailOnError
        Throw when a source cannot be read. Used by write paths that must compare against reliable
        resolved pricing before changing an override.

    .FUNCTIONALITY
        Internal
    #>
    [CmdletBinding()]
    param(
        [string]$SkuId,
        [string]$Currency = 'USD',
        [switch]$ListCurrencies,
        [switch]$IncludeUnknown,
        [switch]$FailOnError
    )

    if ($FailOnError) { $ErrorActionPreference = 'Stop' }

    # currency (lower) -> @{ skuId (lower) -> price object }
    $Estimate = @{}
    $Override = @{}
    # skuId (lower) -> metadata shared across currencies (name / part number)
    $SkuMeta = @{}
    $CurrencySet = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)

    # Every SKU Microsoft publishes (names and part numbers) comes from the shipped SKU list; the
    # catalog only carries prices keyed by GUID, so there is one SKU database, not two.
    try {
        $TablePath = Join-Path $env:CIPPRootPath 'Config\ConversionTable.csv'
        if ($FailOnError -and -not (Test-Path $TablePath)) { throw "SKU list not found at $TablePath" }
        if (Test-Path $TablePath) {
            foreach ($Row in (Get-Content -Path $TablePath -Raw | ConvertFrom-Csv)) {
                $Key = ([string]$Row.GUID).Trim().ToLowerInvariant()
                if ([string]::IsNullOrWhiteSpace($Key) -or $SkuMeta.ContainsKey($Key)) { continue }
                $SkuMeta[$Key] = [pscustomobject]@{ skuPartNumber = [string]$Row.String_Id; Product_Display_Name = [string]$Row.Product_Display_Name }
            }
        }
    } catch {
        if ($FailOnError) { throw "Get-CIPPLicensePrice: failed to read the SKU list: $($_.Exception.Message)" }
        Write-Information "Get-CIPPLicensePrice: failed to read the SKU list: $($_.Exception.Message)"
    }

    # Shipped list prices (public, subject to drift - labelled Estimate)
    try {
        $Catalog = Get-CIPPLicenseCatalog
        if ($FailOnError -and $null -eq $Catalog) { throw 'License catalog is unavailable.' }
        $ProductCount = @($Catalog.products | Where-Object { $null -ne $_ }).Count
        if ($FailOnError -and $ProductCount -eq 0) { throw 'License catalog has no products.' }
        foreach ($Product in @($Catalog.products)) {
            $Key = ([string]$Product.skuId).Trim().ToLowerInvariant()
            if ([string]::IsNullOrWhiteSpace($Key)) { continue }
            if (-not $SkuMeta.ContainsKey($Key)) {
                $SkuMeta[$Key] = [pscustomobject]@{ skuPartNumber = [string]$Product.skuPartNumber; Product_Display_Name = if ($Product.name) { [string]$Product.name } else { $Key } }
            }
            if ($null -eq $Product.prices) { continue }
            foreach ($PriceProp in $Product.prices.PSObject.Properties) {
                $Cur = [string]$PriceProp.Name
                if ([string]::IsNullOrWhiteSpace($Cur) -or $null -eq $PriceProp.Value) { continue }
                $null = $CurrencySet.Add($Cur)
                $CurKey = $Cur.ToLowerInvariant()
                if (-not $Estimate.ContainsKey($CurKey)) { $Estimate[$CurKey] = @{} }
                $Estimate[$CurKey][$Key] = [pscustomobject]@{
                    skuId                = $Key
                    skuPartNumber        = $SkuMeta[$Key].skuPartNumber
                    Product_Display_Name = $SkuMeta[$Key].Product_Display_Name
                    MonthlyPrice         = [double]$PriceProp.Value
                    Currency             = $Cur
                    Source               = 'Estimate'
                }
            }
        }
    } catch {
        if ($FailOnError) { throw "Get-CIPPLicensePrice: failed to read the license catalog: $($_.Exception.Message)" }
        Write-Information "Get-CIPPLicensePrice: failed to read the license catalog: $($_.Exception.Message)"
    }

    # MSP overrides (win over estimates, per currency)
    try {
        $Table = Get-CIPPTable -TableName 'LicensePricing'
        foreach ($Row in (Get-CIPPAzDataTableEntity @Table)) {
            $Key = if ($Row.skuId) { ([string]$Row.skuId).Trim().ToLowerInvariant() } else { (([string]$Row.RowKey) -replace '-[^-]+$', '').Trim().ToLowerInvariant() }
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
        if ($FailOnError) { throw "Get-CIPPLicensePrice: failed to read override table: $($_.Exception.Message)" }
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
        return & $ResolveOne ([string]$SkuId).Trim().ToLowerInvariant()
    }

    # The full list is the price matrix: only SKUs that actually carry a price in this currency
    # (a SKU priced in USD but not the requested currency is omitted, not shown as 'Unknown').
    $Result = foreach ($Sku in $SkuMeta.Keys) { & $ResolveOne $Sku }
    if ($IncludeUnknown) { return @($Result | Sort-Object -Property Product_Display_Name) }
    return @($Result | Where-Object { $null -ne $_.MonthlyPrice } | Sort-Object -Property Product_Display_Name)
}
