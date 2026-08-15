# Static invariants over Config/BaselineStandards. These are cheap and they guard the three
# ways a definition can be silently wrong - wrong in the sense that nothing throws, nothing
# logs, and the standard simply stops doing its job on every tenant:
#
#   1. A missing 'requiredCapabilities' property. @($null).Count is 1, so the licence gate
#      builds a group containing $null, no capability matches it, and the standard is scored
#      'Skipped - No License' forever.
#   2. A prepare hook or executor whose function does not exist. Both are resolved by naming
#      convention at REMEDIATION time, so a typo surfaces as a failed write against a live
#      tenant rather than at authoring time - the switch statement this replaced at least
#      failed loudly in code review.
#   3. A read.cacheType with no collector, which disables collector-on-miss and parks the
#      standard at 'No Data' until some other standard happens to populate the same type.

BeforeAll {
    $script:RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
    $RepoRoot = $script:RepoRoot

    $script:Definitions = Get-ChildItem -Path (Join-Path $RepoRoot 'Config/BaselineStandards') -Recurse -Filter '*.json' | ForEach-Object {
        [PSCustomObject]@{
            File       = $_
            Name       = $_.BaseName
            Definition = Get-Content $_.FullName -Raw | ConvertFrom-Json
        }
    }
    $script:BaselineFunctions = (Get-ChildItem -Path (Join-Path $RepoRoot 'Modules/CIPPCore/Public/Baselines') -Filter '*.ps1').BaseName
    $script:CollectorFunctions = (Get-ChildItem -Path (Join-Path $RepoRoot 'Modules/CIPPDB/Public/DBCache') -Filter '*.ps1').BaseName
}

Describe 'Baseline definition catalog' {

    It 'has at least one definition to check' {
        @($script:Definitions).Count | Should -BeGreaterThan 0
    }

    It 'gives every definition a name matching its filename' {
        # Get-CIPPBaselineDefinition looks a standard up by file BaseName, so a definition
        # whose 'name' disagrees can never be resolved by the work-item resolver.
        $Mismatched = @($script:Definitions | Where-Object { $_.Definition.name -ne $_.Name } | ForEach-Object { "$($_.Name) declares name '$($_.Definition.name)'" })
        $Mismatched | Should -BeNullOrEmpty
    }

    It 'declares every standard name exactly once' {
        $Duplicated = @($script:Definitions.Definition.name | Group-Object | Where-Object Count -gt 1 | ForEach-Object { $_.Name })
        $Duplicated | Should -BeNullOrEmpty
    }

    It 'declares requiredCapabilities on every definition, even when empty' {
        # Omitting the property is NOT equivalent to an empty array: the engine's
        # @($Definition.requiredCapabilities) becomes @($null), whose Count is 1, so the
        # standard is skipped as unlicensed on every tenant with no error anywhere.
        $Missing = @($script:Definitions | Where-Object { $_.Definition.PSObject.Properties.Name -notcontains 'requiredCapabilities' } | ForEach-Object { $_.Name })
        $Missing | Should -BeNullOrEmpty
    }

    It 'resolves every prepare hook to a function, under the name guard the engine enforces' {
        $Broken = @($script:Definitions | Where-Object { $_.Definition.prepare } | Where-Object {
                $_.Definition.prepare -notmatch '^Get-CIPPBaseline[A-Za-z0-9]+$' -or
                $script:BaselineFunctions -notcontains $_.Definition.prepare
            } | ForEach-Object { "$($_.Name) -> $($_.Definition.prepare)" })
        $Broken | Should -BeNullOrEmpty
    }

    It 'resolves every remediate executor to an Invoke-CIPPBaseline function' {
        $Broken = @($script:Definitions | Where-Object { $_.Definition.remediate.executor } | Where-Object {
                $_.Definition.remediate.executor -notmatch '^[A-Za-z0-9]+$' -or
                $script:BaselineFunctions -notcontains "Invoke-CIPPBaseline$($_.Definition.remediate.executor)"
            } | ForEach-Object { "$($_.Name) -> Invoke-CIPPBaseline$($_.Definition.remediate.executor)" })
        $Broken | Should -BeNullOrEmpty
    }

    It 'resolves every delete executor to an Invoke-CIPPBaselineDelete function' {
        $Broken = @($script:Definitions | Where-Object { $_.Definition.delete.executor } | Where-Object {
                $_.Definition.delete.executor -notmatch '^[A-Za-z0-9]+$' -or
                $script:BaselineFunctions -notcontains "Invoke-CIPPBaselineDelete$($_.Definition.delete.executor)"
            } | ForEach-Object { "$($_.Name) -> Invoke-CIPPBaselineDelete$($_.Definition.delete.executor)" })
        $Broken | Should -BeNullOrEmpty
    }

    It 'backs every read.cacheType with a Set-CIPPDBCache collector' {
        # Without one the engine cannot collect on a cache miss, so the standard parks at
        # 'No Data' on its first pass instead of running.
        $Broken = @($script:Definitions | Where-Object { $_.Definition.read.cacheType } | Where-Object {
                $script:CollectorFunctions -notcontains "Set-CIPPDBCache$($_.Definition.read.cacheType)"
            } | ForEach-Object { "$($_.Name) -> Set-CIPPDBCache$($_.Definition.read.cacheType)" } | Sort-Object -Unique)
        $Broken | Should -BeNullOrEmpty
    }

    It 'gives every non-package, non-manual definition something to compare' {
        $Broken = @($script:Definitions | Where-Object {
                -not $_.Definition.package -and -not $_.Definition.manual -and
                -not $_.Definition.expected -and -not $_.Definition.prepare
            } | ForEach-Object { $_.Name })
        $Broken | Should -BeNullOrEmpty
    }

    It 'requires a value for every variable that has no default' {
        # An unrequired variable with no default renders as the literal "%var%" token: the
        # engine only gates variables marked required, so an unmarked one reaches the compare
        # as permanent drift and the write as a garbage string.
        $Broken = @($script:Definitions | ForEach-Object {
                $Name = $_.Name
                ($_.Definition.variables ?? [PSCustomObject]@{}).PSObject.Properties | Where-Object {
                    $_.Value.required -ne $true -and -not $_.Value.PSObject.Properties['default'] -and -not $_.Value.PSObject.Properties['omitWhenBlank']
                } | ForEach-Object { "$Name.$($_.Name)" }
            })
        $Broken | Should -BeNullOrEmpty
    }
}

Describe 'Baseline executor contract' {

    It 'exposes Remediate, TenantFilter and Current on every executor' {
        # The engine calls every executor with the same three named arguments. A new executor
        # that omits -Current fails at remediation time with a parameter-binding error, on a
        # live tenant - nothing binds this contract but this test.
        $Executors = @($script:Definitions | ForEach-Object { $_.Definition.remediate.executor } | Where-Object { $_ } | Sort-Object -Unique | ForEach-Object { "Invoke-CIPPBaseline$_" })
        $Executors.Count | Should -BeGreaterThan 0

        $Broken = @(foreach ($Executor in $Executors) {
                $Path = Join-Path $script:RepoRoot "Modules/CIPPCore/Public/Baselines/$Executor.ps1"
                if (-not (Test-Path $Path)) { "$Executor (file missing)"; continue }
                $Errors = $null
                $Ast = [System.Management.Automation.Language.Parser]::ParseFile($Path, [ref]$null, [ref]$Errors)
                $Function = $Ast.FindAll({ param($n) $n -is [System.Management.Automation.Language.FunctionDefinitionAst] }, $true) | Select-Object -First 1
                $Parameters = @($Function.Body.ParamBlock.Parameters.Name.VariablePath.UserPath)
                foreach ($Required in @('Remediate', 'TenantFilter', 'Current')) {
                    if ($Parameters -notcontains $Required) { "$Executor is missing -$Required" }
                }
            })
        $Broken | Should -BeNullOrEmpty
    }
}
