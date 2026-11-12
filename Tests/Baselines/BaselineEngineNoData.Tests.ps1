# A prepare hook that returns no Current WITH a NoDataReason is saying it cannot grade. The engine
# reports that as an Error (the tenant is licensed by then) and never runs the executor against no
# data. A null Current WITHOUT a reason keeps its old meaning (create-if-missing) and still remediates.

BeforeAll {
    $script:RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))

    function Write-LogMessage { param($API, $tenant, $message, $Sev, $LogData) }
    function Set-CippBaselineRunContext { param($RunId) }
    function Get-CippTable { param($tablename) @{} }
    function ConvertTo-CIPPODataFilterValue { param($Value, $Type) "$Value" }
    function Get-CIPPAzDataTableEntity { param($Filter) }
    function Remove-CIPPAzDataTableEntity { param($Entity, [switch]$Force) }
    function Add-CIPPBaselineHistoryEvent { param($TenantFilter, $Standard, $Mode, $TriggeredBy, $Outcome, $Detail, $RunId, $Remediated) }
    function Set-CIPPBaselineResult { param($Result, $Prior, $RunId, $Detail) }
    function Send-CIPPBaselineAlert { param($Result) }
    function New-CIPPDbRequest { param($TenantFilter, $Type, $Fields) }
    function Get-CIPPTextReplacement { param($TenantFilter, $Text, [switch]$EscapeForJson) $Text }
    function Get-CIPPTenantCapabilities { param($TenantFilter) }
    function Get-CIPPBaselineDefinition { param($Name) }
    function Wait-CIPPBaselineCacheReady { param($TenantFilter, $Definition, $RunId) $false }
    function Get-CippException { param($Exception) }
    function Set-CIPPDBCacheOneDriveQuotas { param($TenantFilter) }
    function Get-CIPPBaselineOneDriveLicensedQuotaState { param($Item, $TenantFilter) }
    function Invoke-CIPPBaselineOneDriveLicensedQuota { param($Remediate, $TenantFilter, $Current) }

    . (Join-Path $script:RepoRoot 'Modules/CIPPCore/Public/Get-CIPPIntuneCompareExclusions.ps1')
    . (Join-Path $script:RepoRoot 'Modules/CIPPCore/Public/Compare-CIPPIntuneObject.ps1')
    . (Join-Path $script:RepoRoot 'Modules/CIPPBaselines/Public/Helpers/Get-CIPPBaselineCommand.ps1')
    . (Join-Path $script:RepoRoot 'Modules/CIPPBaselines/Public/Helpers/Expand-CIPPBaselineToken.ps1')
    . (Join-Path $script:RepoRoot 'Modules/CIPPBaselines/Public/Helpers/Invoke-CIPPBaselineStandard.ps1')

    $script:Definition = Get-Content (Join-Path $script:RepoRoot 'Config/BaselineStandards/SharePoint Standards/OneDriveLicensedQuota.json') -Raw | ConvertFrom-Json
    function New-EngineItem {
        @{ TenantFilter = 'contoso.onmicrosoft.com'; Standard = 'OneDriveLicensedQuota'; BaseName = 'OneDriveLicensedQuota'; Variables = [PSCustomObject]@{}; Tiers = @(); AlertEnabled = $false; RemediateEnabled = $true }
    }
}

Describe 'Engine: a prepare hook that cannot grade' {
    BeforeEach {
        Mock Get-CIPPBaselineDefinition { $script:Definition }
        Mock Get-CIPPAzDataTableEntity { @() }
        Mock Set-CIPPBaselineResult {}
        Mock Add-CIPPBaselineHistoryEvent {}
        Mock Send-CIPPBaselineAlert {}
        Mock Write-LogMessage {}
        Mock Set-CIPPDBCacheOneDriveQuotas {}
        Mock Get-CIPPTenantCapabilities { [PSCustomObject]@{ SHAREPOINTENTERPRISE = $true } }
        Mock Invoke-CIPPBaselineOneDriveLicensedQuota {}
        Mock Get-CIPPBaselineOneDriveLicensedQuotaState { @{ Current = $null; NoDataReason = 'the Users cache has no data for this tenant' } }
    }

    It 'records an Error with the reason and never runs the executor (<Mode>)' -ForEach @(
        @{ Mode = 'run' }
        @{ Mode = 'compare' }
    ) {
        $Result = Invoke-CIPPBaselineStandard -Item (New-EngineItem) -Mode $Mode -Force

        $Result.Outcome | Should -Be 'Error'
        $Result.Status | Should -Be 'Error'
        $Result.Remediated | Should -BeFalse
        Should -Invoke Invoke-CIPPBaselineOneDriveLicensedQuota -Times 0 -Exactly
        Should -Invoke Set-CIPPBaselineResult -Times 1 -Exactly -ParameterFilter { $Detail -eq 'Error: the Users cache has no data for this tenant' }
    }

    It 're-collects the cache once before giving up when the data itself is missing' {
        Invoke-CIPPBaselineStandard -Item (New-EngineItem) -Mode 'compare' | Out-Null
        Should -Invoke Set-CIPPDBCacheOneDriveQuotas -Times 1 -Exactly
    }

    It 'does not re-collect for a configuration problem, which fresh data cannot fix' {
        Mock Get-CIPPBaselineOneDriveLicensedQuotaState { @{ Current = $null; NoDataReason = 'the selected template could not be found'; ConfigError = $true } }

        $Result = Invoke-CIPPBaselineStandard -Item (New-EngineItem) -Mode 'run' -Force

        Should -Invoke Set-CIPPDBCacheOneDriveQuotas -Times 0 -Exactly
        Should -Invoke Get-CIPPBaselineOneDriveLicensedQuotaState -Times 1 -Exactly
        $Result.Status | Should -Be 'Error'
        Should -Invoke Invoke-CIPPBaselineOneDriveLicensedQuota -Times 0 -Exactly
    }

    It 'keeps a null Current without a reason as create-if-missing: the executor still runs' {
        Mock Get-CIPPBaselineOneDriveLicensedQuotaState { @{ Current = $null } }

        $Result = Invoke-CIPPBaselineStandard -Item (New-EngineItem) -Mode 'run'

        Should -Invoke Invoke-CIPPBaselineOneDriveLicensedQuota -Times 1 -Exactly
        $Result.Remediated | Should -BeTrue
    }

    It 'grades normally when the hook has data' {
        Mock Get-CIPPBaselineOneDriveLicensedQuotaState { @{ Current = [PSCustomObject]@{ offenders = @(); targets = @() } } }

        $Result = Invoke-CIPPBaselineStandard -Item (New-EngineItem) -Mode 'compare'

        $Result.Status | Should -Be 'Compliant'
    }
}

Describe 'Engine: capabilities the prepared item needs' {
    BeforeEach {
        Mock Get-CIPPBaselineDefinition { $script:Definition }
        Mock Get-CIPPAzDataTableEntity { @() }
        Mock Set-CIPPBaselineResult {}
        Mock Add-CIPPBaselineHistoryEvent {}
        Mock Send-CIPPBaselineAlert {}
        Mock Write-LogMessage {}
        Mock Invoke-CIPPBaselineOneDriveLicensedQuota {}
        Mock Get-CIPPBaselineOneDriveLicensedQuotaState { @{ Current = [PSCustomObject]@{ offenders = @(); targets = @() }; RequiredCapabilities = @('AAD_PREMIUM_P2') } }
    }

    It 'skips as unlicensed without grading or remediating when the tenant lacks them' {
        Mock Get-CIPPTenantCapabilities { [PSCustomObject]@{ SHAREPOINTENTERPRISE = $true; AAD_PREMIUM = $true } }

        $Result = Invoke-CIPPBaselineStandard -Item (New-EngineItem) -Mode 'run' -Force

        $Result.Status | Should -Be 'Skipped - No License'
        $Result.LicenseAvailable | Should -BeFalse
        Should -Invoke Invoke-CIPPBaselineOneDriveLicensedQuota -Times 0 -Exactly
        Should -Invoke Set-CIPPBaselineResult -Times 1 -Exactly -ParameterFilter { $Result.Status -eq 'Skipped - No License' }
    }

    It 'grades normally when the tenant has them' {
        Mock Get-CIPPTenantCapabilities { [PSCustomObject]@{ SHAREPOINTENTERPRISE = $true; AAD_PREMIUM_P2 = $true } }

        (Invoke-CIPPBaselineStandard -Item (New-EngineItem) -Mode 'compare').Status | Should -Be 'Compliant'
    }

    It 'reads a flat list as any-of' {
        Mock Get-CIPPBaselineOneDriveLicensedQuotaState { @{ Current = [PSCustomObject]@{ offenders = @(); targets = @() }; RequiredCapabilities = @('AAD_PREMIUM_P2', 'Entra_Premium_Internet_Access') } }
        Mock Get-CIPPTenantCapabilities { [PSCustomObject]@{ SHAREPOINTENTERPRISE = $true; Entra_Premium_Internet_Access = $true } }

        (Invoke-CIPPBaselineStandard -Item (New-EngineItem) -Mode 'compare').Status | Should -Be 'Compliant'
    }

    It 'requires every nested group, as the definition-level check does' {
        Mock Get-CIPPBaselineOneDriveLicensedQuotaState { @{ Current = [PSCustomObject]@{ offenders = @(); targets = @() }; RequiredCapabilities = @(@('AAD_PREMIUM_P2'), @('Entra_Premium_Internet_Access')) } }
        Mock Get-CIPPTenantCapabilities { [PSCustomObject]@{ SHAREPOINTENTERPRISE = $true; AAD_PREMIUM_P2 = $true } }
        (Invoke-CIPPBaselineStandard -Item (New-EngineItem) -Mode 'compare').Status | Should -Be 'Skipped - No License'

        Mock Get-CIPPTenantCapabilities { [PSCustomObject]@{ SHAREPOINTENTERPRISE = $true; AAD_PREMIUM_P2 = $true; Entra_Premium_Internet_Access = $true } }
        (Invoke-CIPPBaselineStandard -Item (New-EngineItem) -Mode 'compare').Status | Should -Be 'Compliant'
    }

    It 'reads a group list the prepare hook built as a List' {
        Mock Get-CIPPBaselineOneDriveLicensedQuotaState {
            $Groups = [System.Collections.Generic.List[object]]::new()
            $Groups.Add(@('Entra_Premium_Internet_Access'))
            @{ Current = [PSCustomObject]@{ offenders = @(); targets = @() }; RequiredCapabilities = $Groups }
        }
        Mock Get-CIPPTenantCapabilities { [PSCustomObject]@{ SHAREPOINTENTERPRISE = $true; AAD_PREMIUM_P2 = $true } }
        (Invoke-CIPPBaselineStandard -Item (New-EngineItem) -Mode 'compare').Status | Should -Be 'Skipped - No License'
    }
}