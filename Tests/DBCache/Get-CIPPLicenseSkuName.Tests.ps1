BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))

    function Get-CIPPTable { param($TableName) @{ TableName = $TableName } }
    function Get-CIPPAzDataTableEntity { param($TableName, $Filter, $Property) }
    function Add-CIPPAzDataTableEntity { param($TableName, $Entity, [switch]$Force) }
    function Get-Tenants { param($TenantFilter, [switch]$IncludeErrors) }

    . (Join-Path $RepoRoot 'Modules/CIPPCore/Public/Get-CIPPLicenseSkuName.ps1')
    . (Join-Path $RepoRoot 'Modules/CIPPCore/Public/Get-CIPPConversionTable.ps1')
    $script:SavedRoot = $env:CIPPRootPath
    $env:CIPPRootPath = $RepoRoot
    $script:CsvSku = '4b74a65c-8b4a-4fc8-9f6b-5177ed11ddfa'

    $script:Known = '11111111-1111-1111-1111-111111111111'
    $script:Unknown = '22222222-2222-2222-2222-222222222222'
}

AfterAll {
    $env:CIPPRootPath = $script:SavedRoot
}

Describe 'Get-CIPPLicenseSkuName' {
    BeforeEach {
        $script:Reads = [System.Collections.Generic.List[object]]::new()
        $script:Written = $null
        Mock Get-CIPPAzDataTableEntity {
            $script:Reads.Add([PSCustomObject]@{ Table = $TableName; Filter = $Filter })
            if ($TableName -eq 'LicenseSkuNames' -and $Filter -match $script:Known) {
                [PSCustomObject]@{ PartitionKey = 'Sku'; RowKey = $script:Known; DisplayName = 'Known Licence' }
            }
            if ($TableName -eq 'CippReportingDB' -and $Filter -match "PartitionKey eq 'contoso.com'.*$script:Unknown") {
                [PSCustomObject]@{ PartitionKey = 'contoso.com'; RowKey = "LicenseOverview-$script:Unknown"; Data = '{"License":"Backfilled Licence","skuId":"x"}' }
            }
        }
        Mock Add-CIPPAzDataTableEntity { $script:Written = @($Entity) }
        Mock Get-Tenants { [PSCustomObject]@{ defaultDomainName = 'contoso.com' } }
    }

    It 'names a SKU the shipped CSV lists without reading any table, using its current name' {
        $Result = @(Get-CIPPLicenseSkuName -SkuIds $script:CsvSku.ToUpper(), $script:Known -TenantFilter 'contoso.com')

        $Result.skuId | Should -Be @($script:CsvSku, $script:Known)
        $Result[0].displayName | Should -Be 'Microsoft Copilot Studio User License'
        $script:Reads.Count | Should -Be 1
        $script:Reads[0].Filter | Should -Not -Match $script:CsvSku
    }

    It 'reads no table when the CSV names every SKU' {
        @(Get-CIPPLicenseSkuName -SkuIds $script:CsvSku -TenantFilter 'contoso.com').Count | Should -Be 1
        $script:Reads.Count | Should -Be 0
    }

    It 'returns a table hit without reading the reporting cache' {
        $Result = @(Get-CIPPLicenseSkuName -SkuIds $script:Known.ToUpper() -TenantFilter 'contoso.com')

        $Result.Count | Should -Be 1
        $Result[0].skuId | Should -Be $script:Known
        $Result[0].displayName | Should -Be 'Known Licence'
        @($script:Reads | Where-Object Table -EQ 'CippReportingDB').Count | Should -Be 0
        $script:Written | Should -BeNullOrEmpty
    }

    It "reads a miss from the tenant's licence overview row and backfills it" {
        $Result = @(Get-CIPPLicenseSkuName -SkuIds $script:Known, $script:Unknown -TenantFilter 'contoso.com')

        $Result.displayName | Should -Be @('Known Licence', 'Backfilled Licence')
        $DbRead = @($script:Reads | Where-Object Table -EQ 'CippReportingDB')
        $DbRead.Count | Should -Be 1
        $DbRead[0].Filter | Should -BeLike "PartitionKey eq 'contoso.com' and RowKey ge 'LicenseOverview-$script:Unknown'*"
        $script:Written.Count | Should -Be 1
        $script:Written[0].RowKey | Should -Be $script:Unknown
        $script:Written[0].DisplayName | Should -Be 'Backfilled Licence'
    }

    It 'does not search the reporting cache without a single tenant' {
        foreach ($Tenant in @($null, 'AllTenants')) {
            @(Get-CIPPLicenseSkuName -SkuIds $script:Unknown -TenantFilter $Tenant).Count | Should -Be 0
        }
        @($script:Reads | Where-Object Table -EQ 'CippReportingDB').Count | Should -Be 0
        $script:Written | Should -BeNullOrEmpty
    }

    It 'reads the name table with one point query per SKU' {
        $Many = @(1..3 | ForEach-Object { '{0:x8}-0000-0000-0000-000000000000' -f $_ })
        $null = Get-CIPPLicenseSkuName -SkuIds $Many

        @($script:Reads | Where-Object Table -EQ 'LicenseSkuNames').Filter | Should -Be @(foreach ($SkuId in $Many) { "PartitionKey eq 'Sku' and RowKey eq '$SkuId'" })
    }

    It 'drops values that are not SKU ids before building the filter' {
        @(Get-CIPPLicenseSkuName -SkuIds "x' or PartitionKey ne '", '').Count | Should -Be 0
        $script:Reads.Count | Should -Be 0
    }
}
