BeforeAll {
    $script:RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))

    function Write-LogMessage { param($API, $tenant, $message, $Sev, $LogData) }
    function Get-CIPPBaselineDefinition { param($Name) }
    function Get-CippTable { param($tablename) @{} }
    function ConvertTo-CIPPODataFilterValue { param($Value, $Type) "$Value" -replace "'", "''" }
    function Get-CIPPAzDataTableEntity { param($Filter) }
    function Remove-CIPPAzDataTableEntity { param($Entity, [switch]$Force) }
    function Set-CIPPBaselineResult { param($Result, $Prior, $RunId, $Detail) }
    function Send-CIPPBaselineAlert { param($Result) }
    function New-CIPPDbRequest { param($TenantFilter, $Type, $Fields) }
    function Get-CIPPTextReplacement { param($TenantFilter, $Text, [switch]$EscapeForJson) $Text }
    function Wait-CIPPBaselineCacheReady { param($TenantFilter, $Definition, $RunId) $false }
    function Invoke-CIPPBaselineTestExec { param($Remediate, $TenantFilter, $Current) }

    . (Join-Path $script:RepoRoot 'Modules/CIPPCore/Public/Get-CIPPIntuneCompareExclusions.ps1')
    . (Join-Path $script:RepoRoot 'Modules/CIPPCore/Public/Compare-CIPPIntuneObject.ps1')
    . (Join-Path $script:RepoRoot 'Modules/CIPPBaselines/Public/Helpers/Get-CIPPBaselineCommand.ps1')
    . (Join-Path $script:RepoRoot 'Modules/CIPPBaselines/Public/Helpers/Expand-CIPPBaselineToken.ps1')
    . (Join-Path $script:RepoRoot 'Modules/CIPPBaselines/Public/Helpers/Invoke-CIPPBaselineStandard.ps1')

    $script:Item = @{
        TenantFilter = 'contoso.onmicrosoft.com'; Standard = 'HoldProbe'; BaseName = 'HoldProbe'
        Variables = [PSCustomObject]@{}; Tiers = @(); AlertEnabled = $false; RemediateEnabled = $true
    }
}

Describe 'Engine: Remediate Now on a partially accepted row' {
    BeforeEach {
        Mock Get-CIPPBaselineDefinition {
            [PSCustomObject]@{
                name = 'HoldProbe'; label = 'Hold Probe'; requiredCapabilities = @(); variables = [PSCustomObject]@{}
                read = [PSCustomObject]@{ cacheType = 'TestCache' }
                expected = [PSCustomObject]@{ A = $true; B = $true }
                remediate = [PSCustomObject]@{ executor = 'TestExec' }
            }
        }
        Mock Get-CIPPAzDataTableEntity {
            [PSCustomObject]@{ RowKey = 'HoldProbe'; Status = 'Partially Accepted'; LastRun = 1; AcceptedPaths = '{"A":{"verdict":"accept"}}' }
        }
        Mock New-CIPPDbRequest { [PSCustomObject]@{ A = $false; B = $false } }
        Mock Set-CIPPBaselineResult { }
        Mock Write-LogMessage { }
        Mock Invoke-CIPPBaselineTestExec { }
    }

    It 'does not write and logs why' {
        $Result = Invoke-CIPPBaselineStandard -Item $script:Item -Mode 'oneoff' -Force

        Should -Invoke Invoke-CIPPBaselineTestExec -Times 0 -Exactly
        $Result.Status | Should -Be 'Partially Accepted'
        Should -Invoke Write-LogMessage -Times 1 -Exactly -ParameterFilter { $Sev -eq 'Warning' -and $message -like '*not remediated*' }
    }
}
