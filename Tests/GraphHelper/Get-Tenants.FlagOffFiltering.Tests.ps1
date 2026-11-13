# Turning the MultiPartner flag off after partners were added leaves Tenants rows behind that are
# owned by a non-primary partner. Get-Tenants hides those rows instead of handing them to the
# single-partner code path, and only reads the flag when such a row is actually present so the
# common single-partner run does not pay for the lookup.

BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))

    function Get-CippTable { param($tablename) }
    function Get-CIPPAzDataTableEntity { param($Context, $Filter, $Property) }
    function Get-AzDataTableEntity { param($Context, $Filter, $Property) }
    function Add-CIPPAzDataTableEntity { param($Context, $Entity, [switch]$Force) }
    function Add-AzDataTableEntity { param($Context, $Entity, [switch]$Force) }
    function Remove-CIPPAzDataTableEntity { param($Context, $Entity, [switch]$Force) }
    function ConvertTo-CIPPODataFilterValue { param($Value, $Type) }
    function Get-CIPPPartnerTenant { param($TenantId) }
    function New-GraphGetRequest { param($uri, $tenantid, $NoAuthCheck) }
    function New-GraphBulkRequest { param($Requests, $tenantid, $NoAuthCheck, $Version) }
    function New-CIPPTenantRow { param($Item, $DefaultDomainName, $InitialDomainName, $RequiresRefresh) }
    function Start-CIPPOrchestrator { param($InputObject) }
    function Write-LogMessage { param($API, $message, $Sev, $level, $LogData, $headers) }
    function Get-CippException { param($Exception) }
    function Get-CIPPFeatureFlag { param($Id) }
    function Clear-CippTokenCache { param($TenantFilter) }

    . (Join-Path $RepoRoot 'Modules/CIPPCore/Public/GraphHelper/Get-Tenants.ps1')

    $script:PrimaryPartner = '11111111-1111-1111-1111-111111111111'
    $script:PartnerB = '22222222-2222-2222-2222-222222222222'

    $script:OriginalTenantId = $env:TenantID
    $env:TenantID = $script:PrimaryPartner

    function New-TestTenantRow {
        param($Name, $PartnerTenantId)
        [PSCustomObject]@{
            RowKey            = $Name
            PartitionKey      = 'Tenants'
            customerId        = $Name
            displayName       = $Name
            defaultDomainName = "$Name.onmicrosoft.com"
            initialDomainName = "$Name.onmicrosoft.com"
            partnerTenantId   = $PartnerTenantId
            RequiresRefresh   = $false
            GraphErrorCount   = 0
            Excluded          = $false
        }
    }
}

AfterAll {
    $env:TenantID = $script:OriginalTenantId
}

Describe 'Get-Tenants with the MultiPartner flag off' {
    BeforeEach {
        Mock Get-CippTable { @{ Context = $tablename } }
        Mock ConvertTo-CIPPODataFilterValue { $Value }
        Mock Add-CIPPAzDataTableEntity {}
        Mock Write-LogMessage {}
        Mock Get-CippException { @{} }
        Mock Clear-CippTokenCache { 0 }

        Mock Get-CIPPAzDataTableEntity {
            if ($Context -eq 'tenantMode') { return [PSCustomObject]@{ state = 'default' } }
            if ($Filter -like '*Excluded eq true*') { return @() }
            if ($Context -eq 'Tenants') { return @($script:CachedRows) }
            return @()
        }
    }

    It 'hides tenants owned by a non-primary partner' {
        $script:CachedRows = @(
            (New-TestTenantRow -Name 'implicit-primary' -PartnerTenantId '')
            (New-TestTenantRow -Name 'explicit-primary' -PartnerTenantId $script:PrimaryPartner)
            (New-TestTenantRow -Name 'partner-b-owned' -PartnerTenantId $script:PartnerB)
        )
        Mock Get-CIPPFeatureFlag { [PSCustomObject]@{ Id = $Id; Enabled = $false } }

        $Result = @(Get-Tenants)

        $Result.customerId | Should -Be @('explicit-primary', 'implicit-primary')
        Should -Invoke Get-CIPPFeatureFlag -Times 1 -Exactly -ParameterFilter { $Id -eq 'MultiPartner' }
    }

    It 'returns every tenant while the flag is on' {
        $script:CachedRows = @(
            (New-TestTenantRow -Name 'implicit-primary' -PartnerTenantId '')
            (New-TestTenantRow -Name 'partner-b-owned' -PartnerTenantId $script:PartnerB)
        )
        Mock Get-CIPPFeatureFlag { [PSCustomObject]@{ Id = $Id; Enabled = $true } }

        $Result = @(Get-Tenants)

        $Result.customerId | Should -Be @('implicit-primary', 'partner-b-owned')
    }

    It 'never reads the flag when no row carries a non-primary partner' {
        $script:CachedRows = @(
            (New-TestTenantRow -Name 'implicit-primary' -PartnerTenantId '')
            (New-TestTenantRow -Name 'explicit-primary' -PartnerTenantId $script:PrimaryPartner)
        )
        Mock Get-CIPPFeatureFlag { [PSCustomObject]@{ Id = $Id; Enabled = $false } }

        $Result = @(Get-Tenants)

        $Result.Count | Should -Be 2
        Should -Invoke Get-CIPPFeatureFlag -Times 0 -Exactly
    }
}
