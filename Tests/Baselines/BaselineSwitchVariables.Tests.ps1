# A baseline switch can be bound to a custom variable (%name%) so one baseline serves tenants that need a different
# value. The tenant's variable resolves to text; the engine must turn it into a real bool before hooks, compare and
# writes see it, and must refuse to run when the tenant has no true/false value for it.

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
    function Get-CIPPTextReplacement { param($TenantFilter, $Text, [switch]$EscapeForJson) }
    function Get-CIPPTenantCapabilities { param($TenantFilter) }
    function Get-CIPPBaselineDefinition { param($Name) }
    function Wait-CIPPBaselineCacheReady { param($TenantFilter, $Definition, $RunId) $false }
    function Get-CippException { param($Exception) }
    function Get-CIPPBaselineSwitchProbeState { param($Item, $TenantFilter) }
    function Invoke-CIPPBaselineSwitchProbe { param($Remediate, $TenantFilter, $Current) }

    . (Join-Path $script:RepoRoot 'Modules/CIPPCore/Public/Get-CIPPIntuneCompareExclusions.ps1')
    . (Join-Path $script:RepoRoot 'Modules/CIPPCore/Public/Compare-CIPPIntuneObject.ps1')
    . (Join-Path $script:RepoRoot 'Modules/CIPPBaselines/Public/Helpers/Get-CIPPBaselineCommand.ps1')
    . (Join-Path $script:RepoRoot 'Modules/CIPPBaselines/Public/Helpers/Expand-CIPPBaselineToken.ps1')
    . (Join-Path $script:RepoRoot 'Modules/CIPPBaselines/Public/Helpers/Invoke-CIPPBaselineStandard.ps1')

    $script:Definition = [PSCustomObject]@{
        name      = 'SwitchProbe'
        label     = 'Switch probe'
        requiredCapabilities = @('SHAREPOINTENTERPRISE')
        variables = [PSCustomObject]@{
            Enabled = [PSCustomObject]@{ type = 'switch'; label = 'Enabled'; default = $false }
            Name    = [PSCustomObject]@{ type = 'textField'; label = 'Name'; omitWhenBlank = $true }
        }
        expected  = [PSCustomObject]@{ enabled = '%Enabled%' }
        prepare   = 'Get-CIPPBaselineSwitchProbeState'
        remediate = [PSCustomObject]@{ executor = 'SwitchProbe'; enabled = '%Enabled%' }
    }
    function New-EngineItem($Enabled) {
        @{ TenantFilter = 'contoso.onmicrosoft.com'; Standard = 'SwitchProbe'; BaseName = 'SwitchProbe'; Variables = [PSCustomObject]@{ Enabled = $Enabled }; Tiers = @(); AlertEnabled = $false; RemediateEnabled = $true }
    }
}

Describe 'Engine: switch variables bound to a custom variable' {
    BeforeEach {
        $script:HookEnabled = 'not called'
        Mock Get-CIPPBaselineDefinition { $script:Definition }
        Mock Get-CIPPAzDataTableEntity { @() }
        Mock Set-CIPPBaselineResult {}
        Mock Add-CIPPBaselineHistoryEvent {}
        Mock Send-CIPPBaselineAlert {}
        Mock Write-LogMessage {}
        Mock Get-CIPPTenantCapabilities { [PSCustomObject]@{ SHAREPOINTENTERPRISE = $true } }
        Mock Invoke-CIPPBaselineSwitchProbe {}
        Mock Get-CIPPTextReplacement { $Text.Replace('%TenantTrue%', 'TRUE').Replace('%TenantNo%', 'no').Replace('%Words%', 'sometimes') }
        Mock Get-CIPPBaselineSwitchProbeState {
            $script:HookEnabled = $Item.Variables.Enabled
            @{ Expected = [PSCustomObject]@{ enabled = $Item.Variables.Enabled }; Current = [PSCustomObject]@{ enabled = $true } }
        }
    }

    It 'hands the hook a real bool for <Value>' -ForEach @(
        @{ Value = '%TenantTrue%'; Expected = $true }
        @{ Value = '%TenantNo%'; Expected = $false }
        @{ Value = 'false'; Expected = $false }
        @{ Value = $true; Expected = $true }
    ) {
        $null = Invoke-CIPPBaselineStandard -Item (New-EngineItem $Value) -Mode 'compare'

        $script:HookEnabled | Should -BeOfType ([bool])
        $script:HookEnabled | Should -Be $Expected
    }

    It 'grades a variable that resolves to the current value as compliant' {
        $Result = Invoke-CIPPBaselineStandard -Item (New-EngineItem '%TenantTrue%') -Mode 'compare'

        $Result.Status | Should -Be 'Compliant'
    }

    It 'stops as not configured, without grading or writing, when the tenant has no true/false value for <Value>' -ForEach @(
        @{ Value = '%Undefined%' }
        @{ Value = '%Words%' }
    ) {
        $Result = Invoke-CIPPBaselineStandard -Item (New-EngineItem $Value) -Mode 'run' -Force

        $Result.Outcome | Should -Be 'Error'
        $script:HookEnabled | Should -Be 'not called'
        Should -Invoke Invoke-CIPPBaselineSwitchProbe -Times 0 -Exactly
        Should -Invoke Set-CIPPBaselineResult -Times 1 -Exactly -ParameterFilter { $Detail -like "Not configured:*Enabled ('*' is not true or false for this tenant)*" }
    }

    It 'leaves text variables as text' {
        $Item = New-EngineItem $true
        $Item.Variables | Add-Member -NotePropertyName Name -NotePropertyValue 'true'
        Mock Get-CIPPBaselineSwitchProbeState { $script:HookName = $Item.Variables.Name; @{ Expected = [PSCustomObject]@{ enabled = $true }; Current = [PSCustomObject]@{ enabled = $true } } }

        $null = Invoke-CIPPBaselineStandard -Item $Item -Mode 'compare'

        $script:HookName | Should -BeOfType ([string])
    }
}
