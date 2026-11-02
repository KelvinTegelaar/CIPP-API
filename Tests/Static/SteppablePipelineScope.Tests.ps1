# Source invariant: where a steppable pipeline may be created.
#
# ScriptBlock.GetSteppablePipeline() captures whichever scope is live at the moment it is called,
# and the writer's begin/process/end blocks are later run against that captured scope. Creating
# one inside the scriptblock of a pipeline stage therefore captures the *upstream command's*
# scope, not the enclosing function's. Begin() and Process() still resolve, because they run
# while the upstream command is on the stack - but by the time End() is called the upstream
# pipeline has completed and its scope is gone, so every command the end block calls dies with
# "The term '...' is not recognized as a name of a cmdlet, function, script file, or executable
# program".
#
# That is a genuinely nasty failure. The DBCache collectors hit it: rows already flushed in
# 100-row batches landed, but the count row and the orphan cleanup never ran, so the cache went
# quietly and permanently short while the logbook showed a missing-cmdlet error that had nothing
# to do with the real problem. Nothing about the calling code looks wrong, and the usual Pester
# style of dot-sourcing a function and stubbing its dependencies into the test session cannot
# reproduce it, because that collapses everything into one session state.
#
# Measured behaviour of the four shapes, with the writer and the collector in separate modules:
#
#   <cross-module command> | ForEach-Object { ...GetSteppablePipeline()... }   BREAKS
#   <same-module command>  | ForEach-Object { ...GetSteppablePipeline()... }   works today
#   $Variable / 1..5       | ForEach-Object { ...GetSteppablePipeline()... }   safe
#   foreach ($x in $Array) { ...GetSteppablePipeline()... }                    safe
#
# This rule flags any command upstream, not only a cross-module one. That is deliberately one
# notch stricter than the measured hazard: whether a callee lives in the same module is not
# visible at the call site and changes the day a helper moves between CIPPCore and its callers,
# and the fix - hoist the writer above the pipeline and gate End() on whether any rows arrived -
# costs nothing. Pipelines fed by a variable or a literal are left alone, since no command scope
# is torn down there.

BeforeAll {
    $BackendRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
    $script:ModuleRoot = Join-Path $BackendRoot 'Modules'
    if (-not (Test-Path $script:ModuleRoot)) { throw "Module root not found at $script:ModuleRoot" }

    function Get-SteppableScopeViolation {
        <#
            Returns one record per GetSteppablePipeline() call that is lexically inside a
            scriptblock passed to a pipeline stage whose upstream element is a command.
        #>
        param(
            [Parameter(Mandatory)][System.Management.Automation.Language.Ast]$Ast,
            [string]$Path = '<inline>'
        )

        $Calls = $Ast.FindAll({
                param($Node)
                $Node -is [System.Management.Automation.Language.InvokeMemberExpressionAst] -and
                $Node.Member -is [System.Management.Automation.Language.StringConstantExpressionAst] -and
                $Node.Member.Value -eq 'GetSteppablePipeline'
            }, $true)

        foreach ($Call in $Calls) {
            $Node = $Call
            while ($null -ne $Node.Parent) {
                $Parent = $Node.Parent

                # A scriptblock handed to a command: ForEach-Object { }, Where-Object { }, etc.
                if ($Node -is [System.Management.Automation.Language.ScriptBlockExpressionAst] -and
                    $Parent -is [System.Management.Automation.Language.CommandAst] -and
                    $Parent.Parent -is [System.Management.Automation.Language.PipelineAst]) {

                    $Elements = $Parent.Parent.PipelineElements
                    $Position = $Elements.IndexOf($Parent)

                    # Only a stage with something upstream of it, and only when that upstream is a
                    # command whose scope will be torn down when the pipeline completes.
                    if ($Position -gt 0 -and $Elements[0] -is [System.Management.Automation.Language.CommandAst]) {
                        [pscustomobject]@{
                            Path     = $Path
                            Line     = $Call.Extent.StartLineNumber
                            Upstream = $Elements[0].GetCommandName()
                            Stage    = $Parent.GetCommandName()
                        }
                        break
                    }
                }

                $Node = $Parent
            }
        }
    }

    function Get-ViolationFromSource {
        param([Parameter(Mandatory)][string]$Source)
        $Ast = [System.Management.Automation.Language.Parser]::ParseInput($Source, [ref]$null, [ref]$null)
        @(Get-SteppableScopeViolation -Ast $Ast)
    }

    # Text prefilter first - parsing every .ps1 under Modules/ to find a handful of call sites
    # would dominate the suite's runtime.
    $script:Candidates = @(
        Get-ChildItem -Path $script:ModuleRoot -Filter '*.ps1' -Recurse -File |
            Select-String -Pattern 'GetSteppablePipeline' -List |
            Select-Object -ExpandProperty Path
    )
}

Describe 'Steppable pipeline scope capture' {

    Context 'the detector itself' {
        # A lint rule that silently stops matching is worse than no rule, so the detector is
        # pinned against the shapes it is meant to separate.

        It 'flags a writer created inside a stage fed by a command' {
            $Violations = Get-ViolationFromSource -Source @'
function Set-Thing {
    $Writer = $null
    New-GraphGetRequest -uri 'x' -Stream | ForEach-Object {
        if ($null -eq $Writer) {
            $Writer = { Add-CIPPDbItem -Type 'T' -AddCount }.GetSteppablePipeline()
            $Writer.Begin($true)
        }
        $Writer.Process($_)
    }
    if ($Writer) { $Writer.End() }
}
'@
            $Violations.Count | Should -Be 1
            $Violations[0].Upstream | Should -Be 'New-GraphGetRequest'
            $Violations[0].Stage | Should -Be 'ForEach-Object'
        }

        It 'accepts a writer created before the pipeline starts' {
            Get-ViolationFromSource -Source @'
function Set-Thing {
    $Count = 0
    $Writer = { Add-CIPPDbItem -Type 'T' -AddCount }.GetSteppablePipeline()
    $Writer.Begin($true)
    try {
        New-GraphGetRequest -uri 'x' -Stream | ForEach-Object { $Count++; $Writer.Process($_) }
        if ($Count -gt 0) { $Writer.End() }
    } finally { $Writer.Dispose() }
}
'@ | Should -BeNullOrEmpty
        }

        It 'accepts a writer created inside a foreach statement' {
            Get-ViolationFromSource -Source @'
function Set-Thing {
    $Writer = $null
    foreach ($Row in $Rows) {
        if ($null -eq $Writer) {
            $Writer = { Add-CIPPDbItem -Type 'T' -AddCount }.GetSteppablePipeline()
            $Writer.Begin($true)
        }
        $Writer.Process($Row)
    }
    if ($Writer) { $Writer.End() }
}
'@ | Should -BeNullOrEmpty
        }

        It 'accepts a stage fed by a variable rather than a command' {
            Get-ViolationFromSource -Source @'
function Set-Thing {
    $Writer = $null
    $Rows | ForEach-Object {
        if ($null -eq $Writer) {
            $Writer = { Add-CIPPDbItem -Type 'T' -AddCount }.GetSteppablePipeline()
            $Writer.Begin($true)
        }
        $Writer.Process($_)
    }
    if ($Writer) { $Writer.End() }
}
'@ | Should -BeNullOrEmpty
        }
    }

    Context 'module sources' {

        It 'has steppable pipeline call sites to inspect' {
            # Guards against the prefilter quietly matching nothing after a refactor.
            $script:Candidates.Count | Should -BeGreaterThan 0
        }

        It 'creates no steppable pipeline inside a pipeline stage fed by a command' {
            $Violations = @(
                foreach ($File in $script:Candidates) {
                    $Errs = $null
                    $Ast = [System.Management.Automation.Language.Parser]::ParseFile($File, [ref]$null, [ref]$Errs)
                    if ($Errs.Count -gt 0) { continue }
                    Get-SteppableScopeViolation -Ast $Ast -Path $File
                }
            )

            $Report = $Violations | ForEach-Object {
                "{0}:{1} - writer created inside '{2}' fed by '{3}'; hoist it above the pipeline and gate End() on the row count" -f
                (Split-Path $_.Path -Leaf), $_.Line, $_.Stage, $_.Upstream
            }

            $Violations.Count | Should -Be 0 -Because "these call sites capture the upstream command's scope:`n$($Report -join "`n")"
        }
    }
}
