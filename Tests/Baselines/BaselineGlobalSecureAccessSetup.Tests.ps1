# GlobalSecureAccessSetup is a single-file definition: the real definition runs through the real
# engine against a mocked NetworkAccess cache row, pinning the verdicts and the GraphRequest spec.

BeforeAll {
    $script:RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))

    function Write-LogMessage { param($API, $tenant, $message, $Sev, $LogData) }
    function Set-CippBaselineRunContext { param($RunId) }
    function Update-CippQueueEntry { param($RowKey, $Status, $Name) }
    function Get-CippTable { param($tablename) @{} }
    function ConvertTo-CIPPODataFilterValue { param($Value, $Type) "$Value" }
    function Get-CIPPAzDataTableEntity { param($Filter) }
    function Remove-CIPPAzDataTableEntity { param($Entity, [switch]$Force) }
    function Add-CIPPBaselineHistoryEvent { param($TenantFilter, $Standard, $Mode, $TriggeredBy, $Outcome, $Detail, $RunId, $Remediated) }
    function Set-CIPPBaselineResult { param($Result, $Prior, $RunId) }
    function Send-CIPPBaselineAlert { param($Result) }
    function New-CIPPDbRequest { param($TenantFilter, $Type, $Fields) }
    function Get-CIPPTextReplacement { param($TenantFilter, $Text, [switch]$EscapeForJson) $Text }
    function Get-CIPPTenantCapabilities { param($TenantFilter) }
    function Get-CIPPBaselineDefinition { param($Name) }
    function Wait-CIPPBaselineCacheReady { param($TenantFilter, $Definition, $RunId) $false }
    function Set-CIPPDBCacheNetworkAccess { param($TenantFilter) }
    function Invoke-CIPPBaselineGraphRequest { param($Remediate, $TenantFilter, $Current) }

    . (Join-Path $script:RepoRoot 'Modules/CIPPCore/Public/Get-CIPPIntuneCompareExclusions.ps1')
    . (Join-Path $script:RepoRoot 'Modules/CIPPCore/Public/Compare-CIPPIntuneObject.ps1')
    . (Join-Path $script:RepoRoot 'Modules/CIPPBaselines/Public/Helpers/Get-CIPPBaselineCommand.ps1')
    . (Join-Path $script:RepoRoot 'Modules/CIPPBaselines/Public/Helpers/Invoke-CIPPBaselineStandard.ps1')

    $script:Tenant = 'contoso.onmicrosoft.com'
    $script:Definition = Get-Content (Join-Path $script:RepoRoot 'Config/BaselineStandards/Global Secure Access/GlobalSecureAccessSetup.json') -Raw | ConvertFrom-Json

    function New-EngineItem($Signaling = [PSCustomObject]@{ label = 'Enabled'; value = 'enabled' }) {
        @{
            TenantFilter = $script:Tenant; Standard = 'GlobalSecureAccessSetup'; BaseName = 'GlobalSecureAccessSetup'
            Variables = [PSCustomObject]@{ signalingStatus = $Signaling }; Tiers = @(); AlertEnabled = $false; RemediateEnabled = $true
        }
    }
    function Set-CachedRow([string]$Onboarding, $Signaling) {
        $script:Row = [PSCustomObject]@{ id = 'networkAccess'; onboardingStatus = $Onboarding; onboarded = $Onboarding -eq 'onboarded'; signalingStatus = $Signaling; profiles = @() }
    }
}

Describe 'GlobalSecureAccessSetup definition' {
    BeforeEach {
        Mock Get-CIPPBaselineDefinition { $script:Definition }
        Mock Get-CIPPAzDataTableEntity { @() }
        Mock Set-CIPPBaselineResult {}
        Mock Add-CIPPBaselineHistoryEvent {}
        Mock Send-CIPPBaselineAlert {}
        Mock Write-LogMessage {}
        Mock Invoke-CIPPBaselineGraphRequest {}
        Mock New-CIPPDbRequest { $script:Row } -ParameterFilter { $Type -eq 'NetworkAccess' }
        Mock Get-CIPPTenantCapabilities { [PSCustomObject]@{ AAD_PREMIUM = $true } }
    }

    It 'is compliant once onboarded with signalling as configured' {
        Set-CachedRow 'onboarded' 'enabled'
        (Invoke-CIPPBaselineStandard -Item (New-EngineItem) -Mode 'compare').Status | Should -Be 'Compliant'
    }

    It 'treats onboarding in progress as compliant, so a running onboarding is never started again' {
        Set-CachedRow 'onboardingInProgress' $null
        (Invoke-CIPPBaselineStandard -Item (New-EngineItem -Signaling 'disabled') -Mode 'compare').Status | Should -Not -Be 'Compliant'
        Set-CachedRow 'onboardingInProgress' 'disabled'
        (Invoke-CIPPBaselineStandard -Item (New-EngineItem -Signaling 'disabled') -Mode 'compare').Status | Should -Be 'Compliant'
    }

    It 'drifts when the tenant is not onboarded or signalling differs' {
        Set-CachedRow 'offboarded' $null
        (Invoke-CIPPBaselineStandard -Item (New-EngineItem) -Mode 'compare').Status | Should -Not -Be 'Compliant'
        Set-CachedRow 'onboarded' 'disabled'
        (Invoke-CIPPBaselineStandard -Item (New-EngineItem) -Mode 'compare').Status | Should -Not -Be 'Compliant'
    }

    It 'onboards, then sets signalling, each step continuing past an already-done error' {
        Set-CachedRow 'offboarded' $null
        $null = Invoke-CIPPBaselineStandard -Item (New-EngineItem) -Mode 'run' -Force
        Should -Invoke Invoke-CIPPBaselineGraphRequest -Times 1 -Exactly -ParameterFilter {
            $Steps = @($Remediate.requests)
            $Steps.Count -eq 2 -and
            $Steps[0].method -eq 'POST' -and $Steps[0].uri -eq 'networkAccess/microsoft.graph.networkaccess.onboard' -and $Steps[0].continueOnError -eq $true -and
            $Steps[1].method -eq 'PATCH' -and $Steps[1].uri -eq 'networkAccess/settings/conditionalAccess' -and $Steps[1].body.signalingStatus -eq 'enabled' -and $Steps[1].continueOnError -eq $true
        }
    }

    It 'needs Entra ID P1 or P2' {
        Set-CachedRow 'onboarded' 'enabled'
        Mock Get-CIPPTenantCapabilities { [PSCustomObject]@{ Entra_Premium_Internet_Access = $true } }
        (Invoke-CIPPBaselineStandard -Item (New-EngineItem) -Mode 'compare').Status | Should -Be 'Skipped - No License'
    }
}
