# Pester tests for Get-CIPPLicensePrice — estimates from CSV, overrides win, unknown SKUs.

BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
    $FunctionPath = Get-ChildItem -Path (Join-Path $RepoRoot 'Modules') -Recurse -Filter 'Get-CIPPLicensePrice.ps1' -File -ErrorAction SilentlyContinue |
        Select-Object -First 1 -ExpandProperty FullName
    if (-not $FunctionPath) { throw 'Could not locate Get-CIPPLicensePrice.ps1 under Modules/' }

    function Get-CIPPTable { param($TableName) }
    function Get-CIPPAzDataTableEntity { param($Filter, $Property) }

    . $FunctionPath

    # The function joins $env:CIPPRootPath to locate the defaults CSV; the CSV read itself is
    # mocked, so any non-empty base path is enough to get past Join-Path.
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
        Mock -CommandName Test-Path -MockWith { $true }
        Mock -CommandName Import-Csv -MockWith {
            @(
                [pscustomobject]@{ skuId = $script:E5; skuPartNumber = 'ENTERPRISEPREMIUM'; Product_Display_Name = 'Office 365 E5'; MonthlyPrice = '38.00'; Currency = 'USD' }
                [pscustomobject]@{ skuId = $script:E3; skuPartNumber = 'ENTERPRISEPACK'; Product_Display_Name = 'Office 365 E3'; MonthlyPrice = '23.00'; Currency = 'USD' }
            )
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
        Mock -CommandName Test-Path -MockWith { $true }
        # E5 priced in USD and AUD; E3 in USD only
        Mock -CommandName Import-Csv -MockWith {
            @(
                [pscustomobject]@{ skuId = $script:E5; skuPartNumber = 'ENTERPRISEPREMIUM'; Product_Display_Name = 'Office 365 E5'; MonthlyPrice = '38.00'; Currency = 'USD' }
                [pscustomobject]@{ skuId = $script:E5; skuPartNumber = 'ENTERPRISEPREMIUM'; Product_Display_Name = 'Office 365 E5'; MonthlyPrice = '60.00'; Currency = 'AUD' }
                [pscustomobject]@{ skuId = $script:E3; skuPartNumber = 'ENTERPRISEPACK'; Product_Display_Name = 'Office 365 E3'; MonthlyPrice = '23.00'; Currency = 'USD' }
            )
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
