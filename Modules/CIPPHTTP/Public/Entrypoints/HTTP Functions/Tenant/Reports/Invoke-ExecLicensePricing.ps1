function Invoke-ExecLicensePricing {
    <#
    .FUNCTIONALITY
        Entrypoint,AnyTenant
    .ROLE
        Tenant.Directory.ReadWrite
    .DESCRIPTION
        Manage MSP-global license price overrides used by the license optimization report.
        SetPrice upserts a per-SKU monthly price; RemovePrice deletes an override so the SKU falls
        back to the shipped MSRP estimate. BulkImport validates or applies a pricing CSV batch.
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $APIName = $Request.Params.CIPPEndpoint
    $Headers = $Request.Headers
    $Table = Get-CIPPTable -TableName 'LicensePricing'
    $ResponseBody = $null

    try {
        # SetPrice or RemovePrice
        $Action = $Request.Body.Action
        if ([string]::IsNullOrWhiteSpace($Action)) { throw 'Action is required.' }
        $SkuId = $null
        $Currency = [string]$Request.Body.Currency
        $RowKey = $null
        if ($Action -ne 'BulkImport') {
            # The SKU GUID (skuId) the price applies to
            $SkuId = ([string]$Request.Body.skuId).ToLowerInvariant()
            if ([string]::IsNullOrWhiteSpace($SkuId)) { throw 'skuId is required.' }

            # Overrides are currency-scoped: one row per (skuId, currency).
            $Currency = if ($Request.Body.Currency) { [string]$Request.Body.Currency } else { 'USD' }
            $RowKey = '{0}-{1}' -f $SkuId, $Currency.ToLowerInvariant()
        }

        switch ($Action) {
            'BulkImport' {
                $Mode = [string]$Request.Body.Mode
                $Currency = [string]$Request.Body.Currency
                $RawRows = $Request.Body.Rows
                $Rows = @($RawRows)
                $Errors = [System.Collections.Generic.List[object]]::new()
                $Candidates = [System.Collections.Generic.List[object]]::new()
                $Unchanged = 0

                if ($Mode -notin @('Validate', 'Apply')) { [void]$Errors.Add([pscustomobject]@{ Row = 0; skuId = $null; Error = 'Mode must be Validate or Apply.' }) }
                if ([string]::IsNullOrWhiteSpace($Currency)) { [void]$Errors.Add([pscustomobject]@{ Row = 0; skuId = $null; Error = 'Currency is required.' }) }
                if ($null -eq $RawRows -or $Rows.Count -eq 0) { [void]$Errors.Add([pscustomobject]@{ Row = 0; skuId = $null; Error = 'Rows are required.' }) }

                if ($Errors.Count -eq 0) {
                    $Currencies = @(Get-CIPPLicensePrice -ListCurrencies -FailOnError)
                    $SupportedCurrency = $Currencies | Where-Object { [string]$_ -ieq $Currency } | Select-Object -First 1
                    if (-not $SupportedCurrency) {
                        [void]$Errors.Add([pscustomobject]@{ Row = 0; skuId = $null; Error = "Currency '$Currency' is not supported." })
                    } else {
                        $Currency = [string]$SupportedCurrency
                        $Resolved = @(Get-CIPPLicensePrice -Currency $Currency -IncludeUnknown -FailOnError)
                        $ResolvedBySku = @{}
                        $AmbiguousSku = @{}
                        foreach ($Item in $Resolved) {
                            $ResolvedGuid = [guid]::Empty
                            if (-not [guid]::TryParse(([string]$Item.skuId).Trim(), [ref]$ResolvedGuid)) { continue }
                            $Key = $ResolvedGuid.ToString('D').ToLowerInvariant()
                            if ($AmbiguousSku.ContainsKey($Key)) { continue }
                            if ($ResolvedBySku.ContainsKey($Key)) {
                                $null = $ResolvedBySku.Remove($Key)
                                $AmbiguousSku[$Key] = $true
                            } else {
                                $ResolvedBySku[$Key] = $Item
                            }
                        }
                        $Seen = @{}

                        for ($Index = 0; $Index -lt $Rows.Count; $Index++) {
                            $Row = $Rows[$Index]
                            $RowNumber = $Index + 1
                            $SkuIdText = if ($null -ne $Row) { [string]$Row.skuId } else { '' }
                            $RowErrors = [System.Collections.Generic.List[string]]::new()
                            if ($null -eq $Row) {
                                [void]$RowErrors.Add('Row is empty.')
                            } else {
                                if ([string]::IsNullOrWhiteSpace($SkuIdText)) { [void]$RowErrors.Add('skuId is required.') }
                                if ([string]::IsNullOrWhiteSpace([string]$Row.skuPartNumber)) { [void]$RowErrors.Add('skuPartNumber is required.') }
                                if ([string]::IsNullOrWhiteSpace([string]$Row.Product_Display_Name)) { [void]$RowErrors.Add('Product_Display_Name is required.') }

                                $RowCurrency = [string]$Row.Currency
                                if ([string]::IsNullOrWhiteSpace($RowCurrency)) {
                                    [void]$RowErrors.Add('Currency is required.')
                                } elseif ($RowCurrency -ine $Currency) {
                                    [void]$RowErrors.Add("Currency must match the selected currency ($Currency).")
                                }

                                $SkuGuid = [guid]::Empty
                                $SkuKey = $null
                                if (-not [string]::IsNullOrWhiteSpace($SkuIdText)) {
                                    if ([guid]::TryParse($SkuIdText.Trim(), [ref]$SkuGuid)) {
                                        $SkuKey = $SkuGuid.ToString('D').ToLowerInvariant()
                                        if ($Seen.ContainsKey($SkuKey)) {
                                            [void]$RowErrors.Add('Duplicate SKU and currency row.')
                                        } else {
                                            $Seen[$SkuKey] = $true
                                        }
                                        if ($AmbiguousSku.ContainsKey($SkuKey)) {
                                            [void]$RowErrors.Add("skuId '$SkuIdText' is ambiguous in the known license list.")
                                        } elseif (-not $ResolvedBySku.ContainsKey($SkuKey)) {
                                            [void]$RowErrors.Add("skuId '$SkuIdText' is not in the known license list.")
                                        }
                                    } else {
                                        [void]$RowErrors.Add("skuId '$SkuIdText' is not a valid GUID.")
                                    }
                                }

                                $HasMonthlyPrice = if ($Row -is [System.Collections.IDictionary]) { $Row.Contains('MonthlyPrice') } else { $null -ne $Row.PSObject.Properties['MonthlyPrice'] }
                                if (-not $HasMonthlyPrice) { [void]$RowErrors.Add('MonthlyPrice is required.') }
                                $RawPrice = $Row.MonthlyPrice
                                $PriceBlank = $null -eq $RawPrice -or [string]::IsNullOrWhiteSpace([string]$RawPrice)
                                $NewPrice = $null
                                if (-not $PriceBlank) {
                                    $PriceText = [Convert]::ToString($RawPrice, [Globalization.CultureInfo]::InvariantCulture)
                                    $ParsedPrice = 0.0
                                    if (-not [double]::TryParse($PriceText, [Globalization.NumberStyles]::Float, [Globalization.CultureInfo]::InvariantCulture, [ref]$ParsedPrice) -or [double]::IsNaN($ParsedPrice) -or [double]::IsInfinity($ParsedPrice)) {
                                        [void]$RowErrors.Add('MonthlyPrice must be a number.')
                                    } elseif ($ParsedPrice -lt 0) {
                                        [void]$RowErrors.Add('MonthlyPrice cannot be negative.')
                                    } else {
                                        $NewPrice = $ParsedPrice
                                    }
                                }

                                $Current = if ($SkuKey -and $ResolvedBySku.ContainsKey($SkuKey)) { $ResolvedBySku[$SkuKey] } else { $null }
                                if ($Mode -eq 'Apply') {
                                    $HasCurrentPrice = if ($Row -is [System.Collections.IDictionary]) { $Row.Contains('CurrentPrice') } else { $null -ne $Row.PSObject.Properties['CurrentPrice'] }
                                    if (-not $HasCurrentPrice) {
                                        [void]$RowErrors.Add('CurrentPrice is required for Apply.')
                                    } else {
                                        $ExpectedRaw = $Row.CurrentPrice
                                        $ExpectedPrice = $null
                                        $ExpectedValid = $true
                                        if ($null -ne $ExpectedRaw -and -not [string]::IsNullOrWhiteSpace([string]$ExpectedRaw)) {
                                            $ExpectedText = [Convert]::ToString($ExpectedRaw, [Globalization.CultureInfo]::InvariantCulture)
                                            $ExpectedValid = [double]::TryParse($ExpectedText, [Globalization.NumberStyles]::Float, [Globalization.CultureInfo]::InvariantCulture, [ref]$ExpectedPrice)
                                        }
                                        if (-not $ExpectedValid -or (($null -eq $Current.MonthlyPrice) -ne ($null -eq $ExpectedPrice)) -or ($null -ne $ExpectedPrice -and $ExpectedPrice -ne [double]$Current.MonthlyPrice)) {
                                            [void]$RowErrors.Add('CurrentPrice changed since review. Validate the import again.')
                                        }
                                    }
                                }

                                if ($Current -and $RowErrors.Count -eq 0) {
                                    if ($PriceBlank) {
                                        if ($null -eq $Current.MonthlyPrice) { $Unchanged++ }
                                        else { [void]$RowErrors.Add('MonthlyPrice is required for a priced license.') }
                                    } elseif ($NewPrice -eq $Current.MonthlyPrice) {
                                        $Unchanged++
                                    } else {
                                        [void]$Candidates.Add([pscustomobject]@{
                                            Row                  = $RowNumber
                                            skuId                = $SkuKey
                                            skuPartNumber        = [string]$Current.skuPartNumber
                                            Product_Display_Name = [string]$Current.Product_Display_Name
                                            Currency             = $Currency
                                            CurrentPrice         = $Current.MonthlyPrice
                                            MonthlyPrice         = [double]$NewPrice
                                        })
                                    }
                                }
                            }

                            foreach ($Message in $RowErrors) {
                                [void]$Errors.Add([pscustomobject]@{ Row = $RowNumber; skuId = $SkuIdText; Error = $Message })
                            }
                        }
                    }
                }

                if ($Errors.Count -gt 0) {
                    $FailedRows = @($Errors | Select-Object -ExpandProperty Row -Unique).Count
                    $StatusCode = [HttpStatusCode]::BadRequest
                    $Result = "License pricing import has $FailedRows invalid row(s). No prices were changed."
                    $ResponseBody = [pscustomobject]@{
                        Results   = $Result
                        Valid     = $false
                        Updated   = 0
                        Unchanged = 0
                        Failed    = $FailedRows
                        Errors    = @($Errors)
                        Changes   = @()
                    }
                } elseif ($Mode -eq 'Validate') {
                    $Result = "Validated $($Rows.Count) row(s): $($Candidates.Count) price change(s), $Unchanged unchanged."
                    $ResponseBody = [pscustomobject]@{
                        Results   = $Result
                        Valid     = $true
                        Updated   = $Candidates.Count
                        Unchanged = $Unchanged
                        Failed    = 0
                        Errors    = @()
                        Changes   = @($Candidates | Select-Object skuId, skuPartNumber, Product_Display_Name, Currency, CurrentPrice, MonthlyPrice)
                    }
                    Write-LogMessage -API $APIName -headers $Headers -message $Result -Sev 'Info'
                } else {
                    $WriteErrors = [System.Collections.Generic.List[object]]::new()
                    $Applied = [System.Collections.Generic.List[object]]::new()
                    $Updated = 0
                    for ($Index = 0; $Index -lt $Candidates.Count; $Index++) {
                        $Candidate = $Candidates[$Index]
                        try {
                            $Entity = @{
                                PartitionKey           = 'Price'
                                RowKey                 = '{0}-{1}' -f $Candidate.skuId, $Currency.ToLowerInvariant()
                                skuId                  = $Candidate.skuId
                                skuPartNumber          = $Candidate.skuPartNumber
                                Product_Display_Name   = $Candidate.Product_Display_Name
                                MonthlyPrice           = [double]$Candidate.MonthlyPrice
                                Currency               = $Currency
                            }
                            Add-CIPPAzDataTableEntity @Table -Entity $Entity -Force
                            $Updated++
                            [void]$Applied.Add([pscustomobject]@{ skuId = $Candidate.skuId; Currency = $Currency; CurrentPrice = $Candidate.CurrentPrice; MonthlyPrice = $Candidate.MonthlyPrice })
                        } catch {
                            $WriteError = Get-CippException -Exception $_
                            [void]$WriteErrors.Add([pscustomobject]@{ Row = $Candidate.Row; skuId = $Candidate.skuId; Error = $WriteError.NormalizedError })
                        }
                    }
                    $WriteFailed = $WriteErrors.Count
                    $Result = "Updated $Updated price(s), skipped $Unchanged unchanged row(s), failed $WriteFailed."
                    $ResponseBody = [pscustomobject]@{
                        Results   = $Result
                        Valid     = $true
                        Updated   = $Updated
                        Unchanged = $Unchanged
                        Failed    = $WriteFailed
                        Errors    = @($WriteErrors)
                        Changes   = @()
                    }
                    $Severity = if ($WriteFailed -gt 0) { 'Error' } else { 'Info' }
                    Write-LogMessage -API $APIName -headers $Headers -message $Result -Sev $Severity -LogData @{ Updated = @($Applied); Errors = @($WriteErrors) }
                }
            }
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
            Body       = $ResponseBody ?? [pscustomobject]@{ 'Results' = $Result }
        })
}
