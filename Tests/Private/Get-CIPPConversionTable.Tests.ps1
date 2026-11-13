# Pester tests for Get-CIPPConversionTable - the shared SKU / service plan lookups built from ConversionTable.csv.

BeforeAll {
    . "$PSScriptRoot/../../Modules/CIPPCore/Public/Get-CIPPConversionTable.ps1"
    $script:SavedRoot = $env:CIPPRootPath
    $env:CIPPRootPath = "$TestDrive"
    New-Item -ItemType Directory -Path (Join-Path $TestDrive 'Config') -Force | Out-Null
    $Nbsp = [char]0xA0
    [System.IO.File]::WriteAllText((Join-Path $TestDrive 'Config/ConversionTable.csv'), @(
            'Product_Display_Name,String_Id,GUID,Service_Plan_Name,Service_Plan_Id,Service_Plans_Included_Friendly_Names'
            "Microsoft Copilot Studio,VIRTUAL_AGENT_BASE`t,3F9F06F5-3C31-472C-985F-62D9C10EC167$Nbsp,CDS_VIRTUAL_AGENT_BASE,0A0A23F6-5FF1-4BB2-9AA0-0F63D3E5A07B,Common Data Service for Copilot Studio"
            'Power Virtual Agent,VIRTUAL_AGENT_BASE,3f9f06f5-3c31-472c-985f-62d9c10ec167,FLOW_VIRTUAL_AGENT_BASE,4b81a949-69a1-4409-ad34-9791a6ec88aa,Power Automate for Virtual Agent'
            'Office 365 E3,ENTERPRISEPACK,6fd2c87f-b296-42f0-b197-1e91e994b900,EXCHANGE_S_ENTERPRISE,efb87545-963c-4e0d-99df-69c6916d9eb0,Exchange Online (Plan 2)'
        ) -join "`n")
    $script:Table = Get-CIPPConversionTable
}

AfterAll {
    $env:CIPPRootPath = $script:SavedRoot
}

Describe 'Get-CIPPConversionTable' {
    It 'names a renamed SKU by its first (current) row, keyed by trimmed, lower-cased GUID and trimmed part number' {
        $script:Table.NameBySkuId['3f9f06f5-3c31-472c-985f-62d9c10ec167'] | Should -Be 'Microsoft Copilot Studio'
        $script:Table.NameByPartNumber['VIRTUAL_AGENT_BASE'] | Should -Be 'Microsoft Copilot Studio'
        $script:Table.PartNumberBySkuId['3f9f06f5-3c31-472c-985f-62d9c10ec167'] | Should -Be 'VIRTUAL_AGENT_BASE'
        $script:Table.NameBySkuId.Count | Should -Be 2
    }

    It 'collects every service plan of a SKU across its rows and maps plan ids and names to friendly names' {
        @($script:Table.PlanIdsBySkuId['3f9f06f5-3c31-472c-985f-62d9c10ec167']) | Should -Be @('0a0a23f6-5ff1-4bb2-9aa0-0f63d3e5a07b', '4b81a949-69a1-4409-ad34-9791a6ec88aa')
        $script:Table.PlanNameByPlanId['efb87545-963c-4e0d-99df-69c6916d9eb0'] | Should -Be 'Exchange Online (Plan 2)'
        $script:Table.PlanNameByName['FLOW_VIRTUAL_AGENT_BASE'] | Should -Be 'Power Automate for Virtual Agent'
    }

    It 'parses the file once and returns the cached maps afterwards' {
        Remove-Item (Join-Path $TestDrive 'Config/ConversionTable.csv')
        [object]::ReferenceEquals((Get-CIPPConversionTable), $script:Table) | Should -BeTrue
    }
}
