# Pester tests for Get-CIPPIntuneDeployableType
#
# The list this returns is a copy of the branch labels in Set-CIPPIntunePolicy's dispatch switch, and
# a copy that silently disagrees with its original is worse than no copy at all: a type present in the
# switch but missing from the list gets refused on save even though it deploys perfectly well, and a
# type present in the list but missing from the switch is accepted on save and then deploys nothing.
#
# So rather than trusting the two to be maintained together, this reads the switch back out of the
# source with the AST and compares them.

BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
    $Public = Join-Path $RepoRoot 'Modules/CIPPCore/Public'
    . (Join-Path $Public 'Get-CIPPIntuneDeployableType.ps1')

    $script:PolicyPath = Join-Path $Public 'Set-CIPPIntunePolicy.ps1'
    $Ast = [System.Management.Automation.Language.Parser]::ParseFile($script:PolicyPath, [ref]$null, [ref]$null)

    $script:DispatchSwitch = $Ast.FindAll({
            param($Node)
            $Node -is [System.Management.Automation.Language.SwitchStatementAst] -and
            $Node.Condition.Extent.Text -eq '$TemplateType'
        }, $true) | Select-Object -First 1
}

Describe 'Get-CIPPIntuneDeployableType' {

    It 'finds the dispatch switch it is describing' {
        # If this fails the switch was renamed or restructured, and every assertion below is
        # meaningless until this test is pointed at whatever replaced it.
        $script:DispatchSwitch | Should -Not -BeNullOrEmpty -Because "Set-CIPPIntunePolicy should still dispatch on `$TemplateType"
    }

    It 'lists exactly the types the dispatch switch handles' {
        $SwitchLabels = @($script:DispatchSwitch.Clauses | ForEach-Object {
                $_.Item1.Extent.Text.Trim("'", '"')
            })

        $Declared = @(Get-CIPPIntuneDeployableType)

        # Compared case-insensitively and order-independently: the switch is case-insensitive at
        # runtime and the order of the branches is not meaningful.
        $Missing = @($SwitchLabels | Where-Object { $_ -notin $Declared })
        $Extra = @($Declared | Where-Object { $_ -notin $SwitchLabels })

        $Missing | Should -BeNullOrEmpty -Because 'Set-CIPPIntunePolicy deploys these types but Get-CIPPIntuneDeployableType would have them refused on save'
        $Extra | Should -BeNullOrEmpty -Because 'Get-CIPPIntuneDeployableType accepts these types but Set-CIPPIntunePolicy has no branch for them, so they would deploy nothing'
    }

    It 'keeps the default branch that stops an unhandled type reporting success' {
        # Without this the switch falls through, no request is built, and the function returns its
        # success string for a policy that was never sent to Graph.
        $script:DispatchSwitch.Default | Should -Not -BeNullOrEmpty

        $DefaultText = $script:DispatchSwitch.Default.Extent.Text
        $DefaultText | Should -Match 'throw'
    }

    It 'returns a non-empty list of unique names' {
        $Types = @(Get-CIPPIntuneDeployableType)
        $Types.Count | Should -BeGreaterThan 0
        ($Types | Sort-Object -Unique).Count | Should -Be $Types.Count
    }
}
