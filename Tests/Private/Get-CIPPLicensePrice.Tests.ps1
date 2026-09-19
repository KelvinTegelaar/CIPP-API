# Pester tests for Get-CIPPLicensePrice — estimates from the catalog, overrides win, unknown SKUs.

BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
    $FunctionPath = Get-ChildItem -Path (Join-Path $RepoRoot 'Modules') -Recurse -Filter 'Get-CIPPLicensePrice.ps1' -File -ErrorAction SilentlyContinue |
        Select-Object -First 1 -ExpandProperty FullName
    if (-not $FunctionPath) { throw 'Could not locate Get-CIPPLicensePrice.ps1 under Modules/' }

    function Get-CIPPTable { param($TableName) }
    function Get-CIPPAzDataTableEntity { param($Filter, $Property) }
    function Get-CIPPLicenseCatalog { param([switch]$Force) }

    . $FunctionPath

    # The function joins $env:CIPPRootPath to locate the SKU list; the read itself is mocked, so
    # any non-empty base path is enough to get past Join-Path.
    $script:SavedRoot = $env:CIPPRootPath
    $env:CIPPRootPath = "$TestDrive"

    # SKU GUIDs used across the cases
    $script:E5 = '06ebc4ee-1bb5-47dd-8120-11324bc54e06'
    $script:E3 = '6fd2c87f-b296-42f0-b197-1e91e994b900'
}

AfterAll {
    $env:CIPPRootPath = $script:SavedRoot
}

Describe 'Get-CIPPLicensePrice' {
    BeforeEach {
        # No SKU list on disk unless a case provides one
        Mock -CommandName Test-Path -MockWith { $false }
        Mock -CommandName Get-CIPPLicenseCatalog -MockWith {
            [pscustomobject]@{
                products = @(
                    [pscustomobject]@{ skuId = $script:E5; skuPartNumber = 'ENTERPRISEPREMIUM'; name = 'Office 365 E5'; prices = [pscustomobject]@{ USD = 38.00 } }
                    [pscustomobject]@{ skuId = $script:E3; skuPartNumber = 'ENTERPRISEPACK'; name = 'Office 365 E3'; prices = [pscustomobject]@{ USD = 23.00 } }
                )
            }
        }
        Mock -CommandName Get-CIPPTable -MockWith { @{ Context = 'fake' } }
        # Default: no overrides
        Mock -CommandName Get-CIPPAzDataTableEntity -MockWith { @() }
    }

    It 'returns the shipped estimate when no override exists' {
        $Result = Get-CIPPLicensePrice -SkuId $script:E5

        $Result.MonthlyPrice | Should -Be 38.00
        $Result.Source | Should -Be 'Estimate'
        $Result.Currency | Should -Be 'USD'
    }

    It 'lets an override win over the estimate' {
        Mock -CommandName Get-CIPPAzDataTableEntity -MockWith {
            @([pscustomobject]@{ PartitionKey = 'Price'; RowKey = $script:E5; skuId = $script:E5; skuPartNumber = 'ENTERPRISEPREMIUM'; Product_Display_Name = 'Office 365 E5'; MonthlyPrice = 30.0; Currency = 'USD' })
        }

        $Result = Get-CIPPLicensePrice -SkuId $script:E5

        $Result.MonthlyPrice | Should -Be 30.0
        $Result.Source | Should -Be 'Override'
    }

    It 'returns Source Unknown with a null price for an unknown SKU' {
        $Result = Get-CIPPLicensePrice -SkuId '00000000-0000-0000-0000-000000000000'

        $Result.Source | Should -Be 'Unknown'
        $Result.MonthlyPrice | Should -BeNullOrEmpty
    }

    It 'is case-insensitive on the requested SKU GUID' {
        $Result = Get-CIPPLicensePrice -SkuId $script:E5.ToUpper()

        $Result.Source | Should -Be 'Estimate'
        $Result.MonthlyPrice | Should -Be 38.00
    }

    It 'returns every known SKU when no SkuId is given' {
        $Result = @(Get-CIPPLicensePrice)

        $Result.Count | Should -Be 2
        ($Result.skuId | Sort-Object) | Should -Be (@($script:E3, $script:E5) | Sort-Object)
    }

    It 'lists every SKU from the shipped SKU list when IncludeUnknown is set, named from that list' {
        Mock -CommandName Test-Path -MockWith { $true }
        Mock -CommandName Get-Content -MockWith {
            "Product_Display_Name,String_Id,GUID,Service_Plan_Name,Service_Plan_Id`nOffice 365 E5 (from list),ENTERPRISEPREMIUM,$($script:E5),EXCHANGE_S_ENTERPRISE,efb87545`nExchange Online Kiosk,EXCHANGEDESKLESS,80b2d799-d2ba-4d2a-8842-fb0d0f3a4b82,EXCHANGE_S_DESKLESS,4a82b400`nExchange Online Kiosk,EXCHANGEDESKLESS,80b2d799-d2ba-4d2a-8842-fb0d0f3a4b82,INTUNE_O365,882e1d05"
        }

        $Result = @(Get-CIPPLicensePrice -IncludeUnknown)

        $Result.Count | Should -Be 3
        $Kiosk = $Result | Where-Object { $_.skuId -eq '80b2d799-d2ba-4d2a-8842-fb0d0f3a4b82' }
        $Kiosk.Source | Should -Be 'Unknown'
        $Kiosk.MonthlyPrice | Should -BeNullOrEmpty
        $Kiosk.skuPartNumber | Should -Be 'EXCHANGEDESKLESS'
        # The SKU list wins for the display name; the catalog carries prices only
        ($Result | Where-Object { $_.skuId -eq $script:E5 }).Product_Display_Name | Should -Be 'Office 365 E5 (from list)'
        # Without IncludeUnknown the unpriced Kiosk row is omitted
        @(Get-CIPPLicensePrice).Count | Should -Be 2
    }

    It 'merges an override-only SKU into the full list' {
        Mock -CommandName Get-CIPPAzDataTableEntity -MockWith {
            @([pscustomobject]@{ PartitionKey = 'Price'; RowKey = 'aaaa1111-2222-3333-4444-555566667777'; skuId = 'aaaa1111-2222-3333-4444-555566667777'; skuPartNumber = 'CUSTOM'; Product_Display_Name = 'Custom SKU'; MonthlyPrice = 5.0; Currency = 'USD' })
        }

        $Result = @(Get-CIPPLicensePrice)

        $Result.Count | Should -Be 3
        ($Result | Where-Object { $_.skuId -eq 'aaaa1111-2222-3333-4444-555566667777' }).Source | Should -Be 'Override'
    }
}

Describe 'Get-CIPPLicensePrice - multi-currency' {
    BeforeEach {
        Mock -CommandName Test-Path -MockWith { $false }
        # E5 priced in USD and AUD; E3 in USD only
        Mock -CommandName Get-CIPPLicenseCatalog -MockWith {
            [pscustomobject]@{
                products = @(
                    [pscustomobject]@{ skuId = $script:E5; skuPartNumber = 'ENTERPRISEPREMIUM'; name = 'Office 365 E5'; prices = [pscustomobject]@{ USD = 38.00; AUD = 60.00 } }
                    [pscustomobject]@{ skuId = $script:E3; skuPartNumber = 'ENTERPRISEPACK'; name = 'Office 365 E3'; prices = [pscustomobject]@{ USD = 23.00 } }
                )
            }
        }
        Mock -CommandName Get-CIPPTable -MockWith { @{ Context = 'fake' } }
        Mock -CommandName Get-CIPPAzDataTableEntity -MockWith { @() }
    }

    It 'resolves the price in the requested currency' {
        $Result = Get-CIPPLicensePrice -SkuId $script:E5 -Currency 'AUD'

        $Result.MonthlyPrice | Should -Be 60.00
        $Result.Currency | Should -Be 'AUD'
        $Result.Source | Should -Be 'Estimate'
    }

    It 'reports Unknown (no cross-currency fallback) when the SKU lacks the requested currency' {
        $Result = Get-CIPPLicensePrice -SkuId $script:E3 -Currency 'AUD'

        $Result.Source | Should -Be 'Unknown'
        $Result.MonthlyPrice | Should -BeNullOrEmpty
        # SKU metadata is still surfaced so the row remains identifiable
        $Result.skuPartNumber | Should -Be 'ENTERPRISEPACK'
    }

    It 'omits SKUs with no price in the requested currency from the full list' {
        $Result = @(Get-CIPPLicensePrice -Currency 'AUD')

        $Result.Count | Should -Be 1
        ($Result | Where-Object { $_.skuId -eq $script:E3 }) | Should -BeNullOrEmpty
        ($Result | Where-Object { $_.skuId -eq $script:E5 }).MonthlyPrice | Should -Be 60.00
    }

    It 'lists the distinct currencies present' {
        $Result = @(Get-CIPPLicensePrice -ListCurrencies)

        $Result | Should -Be @('AUD', 'USD')
    }

    It 'scopes an override to its currency' {
        Mock -CommandName Get-CIPPAzDataTableEntity -MockWith {
            @([pscustomobject]@{ PartitionKey = 'Price'; RowKey = "$($script:E5)-aud"; skuId = $script:E5; skuPartNumber = 'ENTERPRISEPREMIUM'; Product_Display_Name = 'Office 365 E5'; MonthlyPrice = 55.0; Currency = 'AUD' })
        }

        (Get-CIPPLicensePrice -SkuId $script:E5 -Currency 'AUD').MonthlyPrice | Should -Be 55.0
        (Get-CIPPLicensePrice -SkuId $script:E5 -Currency 'AUD').Source | Should -Be 'Override'
        # USD is untouched by the AUD override
        (Get-CIPPLicensePrice -SkuId $script:E5 -Currency 'USD').MonthlyPrice | Should -Be 38.00
        (Get-CIPPLicensePrice -SkuId $script:E5 -Currency 'USD').Source | Should -Be 'Estimate'
    }
}
