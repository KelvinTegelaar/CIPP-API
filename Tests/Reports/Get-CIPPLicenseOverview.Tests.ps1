# Pester tests for Get-CIPPLicenseOverview
# Focus: the exclusion/dropdown gate that decides which SKUs each caller sees.
#   - Reporting/alert callers (no -IncludeExcluded) drop every excluded SKU.
#   - Picker callers (-IncludeExcluded) keep excluded SKUs so they stay assignable,
#     unless the SKU has been explicitly hidden from the dropdown (ShowInLicenseDropdown = $false).
# Regression guard for free/self-service SKUs (e.g. Power Automate Free) vanishing from the
# add-license picker because they ship as default reporting exclusions.

BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
    $FunctionPath = Join-Path $RepoRoot 'Modules/CIPPCore/Public/Get-CIPPLicenseOverview.ps1'

    # ConversionTable.csv is read directly off disk (not via a mockable command), so point the
    # function at the real backend config. Pretty-name resolution falls back to skuPartNumber for
    # SKUs missing from the CSV, which is all this test relies on.
    $env:CIPPRootPath = $RepoRoot

    # Minimal stubs so Mock has commands to replace (only Get-CIPPLicenseOverview is dot-sourced,
    # not the whole module).
    function New-GraphGetRequest { param($uri, $scope, $TenantID, $AsApp) }
    function New-GraphBulkRequest { param($Requests, $TenantID, $asapp) }
    function Get-CIPPTable { param($TableName) }
    function Get-CIPPAzDataTableEntity { param($Table, $Context, $Filter) }
    function Initialize-CIPPExcludedLicenses { }
    function Get-CIPPLicenseSkuName { param($SkuIds) }
    function Add-CIPPAzDataTableEntity { param($Context, $Entity) }

    . $FunctionPath

    $script:FlowFreeGuid = 'f30db892-07e9-47e9-837c-80727f46fd3d'   # Microsoft Power Automate Free (default exclusion)
    $script:E5Guid = '06ebc4ee-1bb5-47dd-8120-11324bc54e06'         # SPE_E5 (not excluded)

    # Builds the New-GraphBulkRequest response shape from a set of subscribedSkus.
    function New-BulkResult {
        param($Skus)
        @(
            [pscustomobject]@{ id = 'subscribedSkus'; body = [pscustomobject]@{ value = @($Skus) } }
            [pscustomobject]@{ id = 'directorySubscriptions'; body = [pscustomobject]@{ value = @() } }
            [pscustomobject]@{ id = 'licensedUsers'; body = [pscustomobject]@{ value = @() } }
            [pscustomobject]@{ id = 'licensedGroups'; body = [pscustomobject]@{ value = @() } }
        )
    }

    function New-Sku {
        param($SkuId, $PartNumber)
        [pscustomobject]@{
            skuId           = $SkuId
            skuPartNumber   = $PartNumber
            consumedUnits   = 1
            prepaidUnits    = [pscustomobject]@{ enabled = 10000 }
            subscriptionIds = @()
            servicePlans    = @()
        }
    }
}

Describe 'Get-CIPPLicenseOverview exclusion/dropdown gate' {
    BeforeEach {
        $script:Tenant = 'contoso.onmicrosoft.com'
        Mock -CommandName New-GraphGetRequest -MockWith { @() }
        Mock -CommandName Get-CIPPTable -MockWith { @{ TableName = 'ExcludedLicenses' } }
        Mock -CommandName Initialize-CIPPExcludedLicenses -MockWith { }
        Mock -CommandName New-GraphBulkRequest -MockWith {
            New-BulkResult -Skus @(
                (New-Sku -SkuId $script:FlowFreeGuid -PartNumber 'FLOW_FREE'),
                (New-Sku -SkuId $script:E5Guid -PartNumber 'SPE_E5')
            )
        }
    }

    It 'keeps a default-excluded free SKU in the picker (IncludeExcluded) so it stays assignable' {
        # Default-config exclusion: GUID present, no ExcludedEverywhere / ShowInLicenseDropdown set.
        Mock -CommandName Get-CIPPAzDataTableEntity -MockWith {
            @([pscustomobject]@{ GUID = $script:FlowFreeGuid; Product_Display_Name = 'Microsoft Power Automate Free' })
        }

        $Result = Get-CIPPLicenseOverview -TenantFilter $script:Tenant -IncludeExcluded

        @($Result).skuId | Should -Contain $script:FlowFreeGuid
        @($Result).skuId | Should -Contain $script:E5Guid
    }

    It 'drops the excluded SKU from reporting callers (no IncludeExcluded)' {
        Mock -CommandName Get-CIPPAzDataTableEntity -MockWith {
            @([pscustomobject]@{ GUID = $script:FlowFreeGuid; Product_Display_Name = 'Microsoft Power Automate Free' })
        }

        $Result = Get-CIPPLicenseOverview -TenantFilter $script:Tenant

        @($Result).skuId | Should -Not -Contain $script:FlowFreeGuid
        @($Result).skuId | Should -Contain $script:E5Guid
    }

    It 'hides an excluded SKU from the picker only when ShowInLicenseDropdown is explicitly false' {
        Mock -CommandName Get-CIPPAzDataTableEntity -MockWith {
            @([pscustomobject]@{
                    GUID                  = $script:FlowFreeGuid
                    Product_Display_Name  = 'Microsoft Power Automate Free'
                    ShowInLicenseDropdown = $false
                })
        }

        $Result = Get-CIPPLicenseOverview -TenantFilter $script:Tenant -IncludeExcluded

        @($Result).skuId | Should -Not -Contain $script:FlowFreeGuid
        @($Result).skuId | Should -Contain $script:E5Guid
    }

    It 'treats ExcludedEverywhere = false as alert-only, leaving the SKU visible to reporting' {
        Mock -CommandName Get-CIPPAzDataTableEntity -MockWith {
            @([pscustomobject]@{
                    GUID                 = $script:FlowFreeGuid
                    Product_Display_Name = 'Microsoft Power Automate Free'
                    ExcludedEverywhere   = $false
                })
        }

        $Result = Get-CIPPLicenseOverview -TenantFilter $script:Tenant

        @($Result).skuId | Should -Contain $script:FlowFreeGuid
    }
}

Describe 'Get-CIPPLicenseOverview SKU name backfill' {
    BeforeEach {
        $script:KioskGuid = 'bc20d3f7-abea-4597-b474-a35321a50157'   # not in ConversionTable.csv
        Mock -CommandName Initialize-CIPPExcludedLicenses -MockWith { }
        Mock -CommandName Get-CIPPTable -MockWith { @{ Context = $TableName } }
        Mock -CommandName Get-CIPPAzDataTableEntity -MockWith { @() }
        Mock -CommandName Add-CIPPAzDataTableEntity -MockWith { }
        Mock -CommandName New-GraphGetRequest -MockWith {
            @([pscustomobject]@{ aadSkuId = $script:KioskGuid; displayName = 'Exchange Online Kiosk for GCC' })
        }
        Mock -CommandName New-GraphBulkRequest -MockWith {
            New-BulkResult -Skus @(
                (New-Sku -SkuId $script:KioskGuid -PartNumber 'EXCHANGEDESKLESS_GOV'),
                (New-Sku -SkuId $script:E5Guid -PartNumber 'SPE_E5')
            )
        }
    }

    It 'saves a live name the name table does not hold yet' {
        Mock -CommandName Get-CIPPLicenseSkuName -MockWith { [pscustomobject]@{ skuId = $script:E5Guid; displayName = 'Microsoft 365 E5' } }

        $null = Get-CIPPLicenseOverview -TenantFilter 'contoso.onmicrosoft.com'

        Should -Invoke Add-CIPPAzDataTableEntity -Times 1 -Exactly -ParameterFilter {
            $Context -eq 'LicenseSkuNames' -and @($Entity).Count -eq 1 -and
            $Entity[0].RowKey -eq $script:KioskGuid -and $Entity[0].DisplayName -eq 'Exchange Online Kiosk for GCC'
        }
    }

    It 'writes nothing when every name is already known' {
        Mock -CommandName Get-CIPPLicenseSkuName -MockWith { @($SkuIds | ForEach-Object { [pscustomobject]@{ skuId = $_; displayName = 'x' } }) }

        $null = Get-CIPPLicenseOverview -TenantFilter 'contoso.onmicrosoft.com'

        Should -Invoke Add-CIPPAzDataTableEntity -Times 0 -Exactly
    }

    It 'still returns the overview when the name table fails' {
        Mock -CommandName Get-CIPPLicenseSkuName -MockWith { throw 'table down' }

        $Result = Get-CIPPLicenseOverview -TenantFilter 'contoso.onmicrosoft.com'

        @($Result).License | Should -Contain 'Exchange Online Kiosk for GCC'
    }
}
