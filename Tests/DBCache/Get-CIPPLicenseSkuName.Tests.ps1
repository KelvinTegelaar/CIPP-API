BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))

    function Get-CIPPTable { param($TableName) @{ TableName = $TableName } }
    function Get-CIPPAzDataTableEntity { param($TableName, $Filter, $Property) }
    function Add-CIPPAzDataTableEntity { param($TableName, $Entity, [switch]$Force) }
    function Get-Tenants { param($TenantFilter, [switch]$IncludeErrors) }

    . (Join-Path $RepoRoot 'Modules/CIPPCore/Public/Get-CIPPLicenseSkuName.ps1')

    $script:Known = '11111111-1111-1111-1111-111111111111'
    $script:Unknown = '22222222-2222-2222-2222-222222222222'
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

    It 'keeps each name table query within 15 comparisons' {
        $Many = @(1..30 | ForEach-Object { '{0:x8}-0000-0000-0000-000000000000' -f $_ })
        $null = Get-CIPPLicenseSkuName -SkuIds $Many

        $Queries = @($script:Reads | Where-Object Table -EQ 'LicenseSkuNames')
        $Queries.Count | Should -Be 3
        foreach ($Query in $Queries) { ([regex]::Matches($Query.Filter, ' eq ')).Count | Should -BeLessOrEqual 15 }
        (@($Queries.Filter | ForEach-Object { [regex]::Matches($_, "RowKey eq '([^']+)'") | ForEach-Object { $_.Groups[1].Value } }) | Sort-Object) -join ',' | Should -Be (($Many | Sort-Object) -join ',')
    }

    It 'drops values that are not SKU ids before building the filter' {
        @(Get-CIPPLicenseSkuName -SkuIds "x' or PartitionKey ne '", '').Count | Should -Be 0
        $script:Reads.Count | Should -Be 0
    }
}
