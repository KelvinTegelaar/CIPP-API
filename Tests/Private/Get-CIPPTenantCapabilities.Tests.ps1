BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
    Add-Type -Path (Join-Path $RepoRoot 'Shared/CIPPSharp/bin/CIPPSharp.dll')
    . (Join-Path $RepoRoot 'Modules/CIPPCore/Public/Get-CIPPTenantCapabilities.ps1')
    function Get-CIPPTable { @{} }
    function Get-CIPPAzDataTableEntity { $script:Reads++; [pscustomobject]@{ JSON = $script:Json } }
    function New-GraphGetRequest { }
    function Add-CIPPAzDataTableEntity { }

    $script:Json = ConvertTo-Json -Compress -Depth 10 -InputObject @(
        [ordered]@{ skuPartNumber = 'E5'; servicePlans = @(
                [ordered]@{ servicePlanName = 'EXCHANGE_S_ENTERPRISE'; provisioningStatus = 'Success' }
                [ordered]@{ servicePlanName = 'AAD_PREMIUM_P2'; provisioningStatus = 'Disabled' }
                [ordered]@{ servicePlanName = 'Teams1'; provisioningStatus = 'PendingProvisioning' }
            )
        }
        [ordered]@{ skuPartNumber = 'E3'; servicePlans = @(
                [ordered]@{ servicePlanName = 'exchange_s_enterprise'; provisioningStatus = 'Success' }
                [ordered]@{ servicePlanName = 'AAD_PREMIUM'; provisioningStatus = 'Success' }
            )
        }
    )
}

Describe 'Get-CIPPTenantCapabilities' {
    BeforeEach { $script:Reads = 0; $script:CIPPTenantCapabilitiesCache = $null }

    It 'returns the enabled service plans the original pipeline returned' {
        $Org = $script:Json | ConvertFrom-Json
        $Expected = @{}
        foreach ($Plan in ($Org.servicePlans | Where-Object { $_.provisioningStatus -ne 'disabled' } | Sort-Object -Property serviceplanName -Unique)) {
            $Expected."$($Plan.servicePlanName)" = $Plan.provisioningStatus -ne 'disabled'
        }

        $Result = Get-CIPPTenantCapabilities -TenantFilter 'contoso.com'

        @($Result.PSObject.Properties.Name | Sort-Object) | Should -Be @($Expected.Keys | Sort-Object)
        @($Result.PSObject.Properties.Value | Select-Object -Unique) | Should -Be @($true)
        $Result.AAD_PREMIUM_P2 | Should -BeNullOrEmpty
    }

    It 'reads the table once per tenant while the result is fresh' {
        $null = Get-CIPPTenantCapabilities -TenantFilter 'contoso.com'
        $null = Get-CIPPTenantCapabilities -TenantFilter 'contoso.com'
        $null = Get-CIPPTenantCapabilities -TenantFilter 'fabrikam.com'
        $script:Reads | Should -Be 2
    }

    It 'rethrows a failed Graph lookup without requesting it again while fresh' {
        Mock Get-CIPPAzDataTableEntity { $script:Reads++ }
        Mock New-GraphGetRequest { throw 'AADSTS53003: blocked by Conditional Access' }

        { Get-CIPPTenantCapabilities -TenantFilter 'contoso.com' } | Should -Throw '*AADSTS53003*'
        { Get-CIPPTenantCapabilities -TenantFilter 'contoso.com' } | Should -Throw '*AADSTS53003*'
        Should -Invoke New-GraphGetRequest -Times 1 -Exactly
        $script:Reads | Should -Be 1
    }
}
