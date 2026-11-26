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
        TenantFilter = 'contoso.onmicrosoft.com'; Standard = 'AcceptProbe'; BaseName = 'AcceptProbe'
        Variables = [PSCustomObject]@{}; Tiers = @(); AlertEnabled = $true; RemediateEnabled = $true
    }
}

Describe 'Engine: new drift on an Accepted row' {
    BeforeEach {
        Mock Get-CIPPBaselineDefinition {
            [PSCustomObject]@{
                name = 'AcceptProbe'; label = 'Accept Probe'; requiredCapabilities = @(); variables = [PSCustomObject]@{}
                read = [PSCustomObject]@{ cacheType = 'TestCache' }
                expected = [PSCustomObject]@{ A = $true; B = $true }
                remediate = [PSCustomObject]@{ executor = 'TestExec' }
            }
        }
        Mock Set-CIPPBaselineResult { }
        Mock Send-CIPPBaselineAlert { }
        Mock Write-LogMessage { }
        Mock Invoke-CIPPBaselineTestExec { }
    }

    It 'alerts as Partially Accepted when a property outside the accepted ones drifts' {
        Mock Get-CIPPAzDataTableEntity {
            [PSCustomObject]@{ RowKey = 'AcceptProbe'; Status = 'Accepted'; LastRun = 1; AcceptedPaths = '{"A":{"verdict":"accept"}}' }
        }
        Mock New-CIPPDbRequest { [PSCustomObject]@{ A = $false; B = $false } }

        $Result = Invoke-CIPPBaselineStandard -Item $script:Item -Mode 'run'

        $Result.Status | Should -Be 'Partially Accepted'
        $Result.AlertEvent | Should -Be 'Drift'
        Should -Invoke Send-CIPPBaselineAlert -Times 1 -Exactly
        Should -Invoke Invoke-CIPPBaselineTestExec -Times 0 -Exactly
    }

    It 'stays Accepted while only the accepted property deviates' {
        Mock Get-CIPPAzDataTableEntity {
            [PSCustomObject]@{ RowKey = 'AcceptProbe'; Status = 'Accepted'; LastRun = 1; AcceptedPaths = '{"A":{"verdict":"accept"}}' }
        }
        Mock New-CIPPDbRequest { [PSCustomObject]@{ A = $false; B = $true } }

        $Result = Invoke-CIPPBaselineStandard -Item $script:Item -Mode 'run'

        $Result.Status | Should -Be 'Accepted'
        Should -Invoke Send-CIPPBaselineAlert -Times 0 -Exactly
    }

    It 'stays Accepted on any drift when the whole row was accepted' {
        Mock Get-CIPPAzDataTableEntity {
            [PSCustomObject]@{ RowKey = 'AcceptProbe'; Status = 'Accepted'; LastRun = 1; AcceptedPaths = '{}' }
        }
        Mock New-CIPPDbRequest { [PSCustomObject]@{ A = $false; B = $false } }

        $Result = Invoke-CIPPBaselineStandard -Item $script:Item -Mode 'run'

        $Result.Status | Should -Be 'Accepted'
        Should -Invoke Send-CIPPBaselineAlert -Times 0 -Exactly
        Should -Invoke Invoke-CIPPBaselineTestExec -Times 0 -Exactly
    }
}
