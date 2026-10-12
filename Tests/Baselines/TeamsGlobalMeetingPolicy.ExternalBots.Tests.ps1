# ExternalBotAccessMode is an omitWhenBlank variable: existing baselines (blank) must neither
# compare nor write it, and only an explicit choice reaches Set-CsTeamsMeetingPolicy.

BeforeAll {
    $script:RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
    $script:Definition = Get-Content (Join-Path $script:RepoRoot 'Config/BaselineStandards/Teams Standards/TeamsGlobalMeetingPolicy.json') -Raw | ConvertFrom-Json

    # $Render is a scriptblock local to Invoke-CIPPBaselineStandard; lift it out of the real
    # source so the test exercises the production pruning, not a copy.
    $Ast = [System.Management.Automation.Language.Parser]::ParseFile((Join-Path $script:RepoRoot 'Modules/CIPPBaselines/Public/Helpers/Invoke-CIPPBaselineStandard.ps1'), [ref]$null, [ref]$null)
    $Assign = $Ast.Find({ param($n) $n -is [System.Management.Automation.Language.AssignmentStatementAst] -and $n.Left.Extent.Text -eq '$Render' }, $true)
    $script:Render = [scriptblock]::Create($Assign.Right.Expression.Extent.Text.Trim('{', '}'))
    function Get-CIPPTextReplacement { param($TenantFilter, $Text, [switch]$EscapeForJson) $Text }
    function Invoke-Render { param($Template, $Variables) $Definition = $script:Definition; & $script:Render $Template $Variables }
}

Describe 'TeamsGlobalMeetingPolicy ExternalBotAccessMode' {
    It 'is declared omitWhenBlank with a blank default and both Microsoft values' {
        $Variable = $script:Definition.variables.ExternalBotAccessMode
        $Variable.omitWhenBlank | Should -BeTrue
        $Variable.default | Should -Be ''
        @($Variable.options.value) | Should -Contain 'RequireApprovalWhenDetected'
        @($Variable.options.value) | Should -Contain 'AllowAllBots'
    }

    It 'is wired into expected and the Set-CsTeamsMeetingPolicy params' {
        $script:Definition.expected.ExternalBotAccessMode | Should -Be '%ExternalBotAccessMode%'
        $script:Definition.remediate.cmdlets[0].cmdlet | Should -Be 'Set-CsTeamsMeetingPolicy'
        $script:Definition.remediate.cmdlets[0].params.ExternalBotAccessMode | Should -Be '%ExternalBotAccessMode%'
    }

    It 'omits the parameter from expected and params when blank' {
        $Variables = [PSCustomObject]@{ ExternalBotAccessMode = '' }
        (Invoke-Render $script:Definition.expected $Variables).PSObject.Properties.Name | Should -Not -Contain 'ExternalBotAccessMode'
        (Invoke-Render $script:Definition.remediate.cmdlets[0].params $Variables).PSObject.Properties.Name | Should -Not -Contain 'ExternalBotAccessMode'
    }

    It 'includes the chosen value in expected and params' {
        $Variables = [PSCustomObject]@{ ExternalBotAccessMode = 'AllowAllBots' }
        (Invoke-Render $script:Definition.expected $Variables).ExternalBotAccessMode | Should -Be 'AllowAllBots'
        (Invoke-Render $script:Definition.remediate.cmdlets[0].params $Variables).ExternalBotAccessMode | Should -Be 'AllowAllBots'
    }
}
