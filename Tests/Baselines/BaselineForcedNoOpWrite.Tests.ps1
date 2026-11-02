# A manual run forces the write even when the cache already grades the setting compliant.
# Some cmdlets refuse that no-op outright (Set-OrganizationConfig -AutoExpandingArchive throws
# "already enabled"), and the engine used to record the refusal as an Error - a false failure
# on the alignment page after every manual run. These tests pin the fix: a rejected write on a
# pre-graded compliant standard stays Compliant; a rejected write on real drift is still an Error.

BeforeAll {
    $script:RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))

    function Write-LogMessage { param($API, $tenant, $message, $Sev, $LogData) }
    function Set-CippBaselineRunContext { param($RunId) }
    function Get-CIPPBaselineDefinition { param($Name) }
    function Get-CippTable { param($tablename) @{} }
    function ConvertTo-CIPPODataFilterValue { param($Value, $Type) "$Value" -replace "'", "''" }
    function Get-CIPPAzDataTableEntity { param($Filter) }
    function Add-CIPPAzDataTableEntity { param($Entity, [switch]$Force) }
    function Remove-CIPPAzDataTableEntity { param($Entity, [switch]$Force) }
    function Add-CIPPBaselineHistoryEvent { param($TenantFilter, $Standard, $Mode, $TriggeredBy, $Outcome, $Detail, $RunId, $Remediated) }
    function Set-CIPPBaselineResult { param($Result, $Prior, $RunId, $Detail) }
    function Send-CIPPBaselineAlert { param($Result) }
    function New-CIPPDbRequest { param($TenantFilter, $Type, $Fields) }
    function Get-CIPPTextReplacement { param($TenantFilter, $Text, [switch]$EscapeForJson) $Text }
    function Get-CIPPTenantCapabilities { param($TenantFilter) }
    function Wait-CIPPBaselineCacheReady { param($TenantFilter, $Definition, $RunId) $false }
    function Get-CippException { param($Exception) }
    function Invoke-CIPPBaselineTestExec { param($Remediate, $TenantFilter, $Current) }

    . (Join-Path $script:RepoRoot 'Modules/CIPPCore/Public/Get-CIPPIntuneCompareExclusions.ps1')
    . (Join-Path $script:RepoRoot 'Modules/CIPPCore/Public/Compare-CIPPIntuneObject.ps1')
    . (Join-Path $script:RepoRoot 'Modules/CIPPBaselines/Public/Helpers/Get-CIPPBaselineCommand.ps1')
    . (Join-Path $script:RepoRoot 'Modules/CIPPBaselines/Public/Helpers/Invoke-CIPPBaselineStandard.ps1')

    $script:Tenant = 'contoso.onmicrosoft.com'
    $script:Definition = [PSCustomObject]@{
        name                 = 'AutoExpandProbe'; label = 'Enable Auto-expanding archives'
        requiredCapabilities = @()
        variables            = [PSCustomObject]@{}
        read                 = [PSCustomObject]@{ cacheType = 'TestCache' }
        expected             = [PSCustomObject]@{ AutoExpandingArchiveEnabled = $true }
        remediate            = [PSCustomObject]@{ executor = 'TestExec'; cmdlets = @() }
    }
    $script:EngineItem = @{
        TenantFilter = $script:Tenant; Standard = 'AutoExpandProbe'; BaseName = 'AutoExpandProbe'
        Variables = [PSCustomObject]@{}; Tiers = @(); AlertEnabled = $false; RemediateEnabled = $true
    }
}

Describe 'Engine: a forced write the service rejects' {
    BeforeEach {
        Mock Get-CIPPBaselineDefinition { $script:Definition }
        Mock Get-CIPPAzDataTableEntity { @() }
        Mock Set-CIPPBaselineResult { }
        Mock Add-CIPPBaselineHistoryEvent { }
        Mock Send-CIPPBaselineAlert { }
        Mock Write-LogMessage { }
        Mock Invoke-CIPPBaselineTestExec { throw 'Auto-expanding Archive is already enabled for organization.' }
    }

    It 'stays Compliant when the cache already graded the setting compliant' {
        Mock New-CIPPDbRequest { [PSCustomObject]@{ AutoExpandingArchiveEnabled = $true } }

        $Result = Invoke-CIPPBaselineStandard -Item $script:EngineItem -Mode 'run' -Force

        Should -Invoke Invoke-CIPPBaselineTestExec -Times 1 -Exactly
        $Result.Compliant | Should -BeTrue
        $Result.Outcome | Should -Be 'Compliant'
        $Result.Status | Should -Be 'Compliant'
        $Result.Remediated | Should -BeFalse
        Should -Invoke Set-CIPPBaselineResult -Times 1 -Exactly
        Should -Invoke Write-LogMessage -Times 0 -Exactly -ParameterFilter { $Sev -eq 'Error' }
    }

    It 'is still an Error when the setting had actually drifted' {
        Mock New-CIPPDbRequest { [PSCustomObject]@{ AutoExpandingArchiveEnabled = $false } }

        $Result = Invoke-CIPPBaselineStandard -Item $script:EngineItem -Mode 'run' -Force

        $Result.Outcome | Should -Be 'Error'
        $Result.Status | Should -Be 'Error'
        $Result.Compliant | Should -BeFalse
        Should -Invoke Write-LogMessage -Times 1 -Exactly -ParameterFilter { $Sev -eq 'Error' -and $message -like 'Failed to change*' }
    }

    It 'control: a forced write that succeeds on a compliant setting still records Remediated' {
        Mock New-CIPPDbRequest { [PSCustomObject]@{ AutoExpandingArchiveEnabled = $true } }
        Mock Invoke-CIPPBaselineTestExec { }

        $Result = Invoke-CIPPBaselineStandard -Item $script:EngineItem -Mode 'run' -Force

        Should -Invoke Invoke-CIPPBaselineTestExec -Times 1 -Exactly
        $Result.Outcome | Should -Be 'Remediated'
        $Result.Status | Should -Be 'Compliant'
    }
}
