# Source invariants for boolean request flags in HTTP entrypoints.
#
# Two rules, both learned the hard way.
#
# 1. A boolean flag must be compared against the $true/$false *variables*, not the
#    strings 'true'/'false'. The two behave identically at runtime, but the OpenAPI
#    generator infers a field's type from what the code does with it: `-eq $true`
#    yields `boolean`, `-eq 'true'` yields an observed string value. Since the spec
#    feeds Get-CippMcpToolList, the string form ships a mistyped MCP tool contract.
#
# 2. A variable normalised that way holds a real [bool] $false when the parameter is
#    absent, where it previously held $null. $null interpolates into a string as ''
#    but $false interpolates as 'False'. Invoke-ListGroups built its Graph URL as
#    "groups/$($GroupID)/$($members)" and, the moment $Members became a real boolean,
#    every plain list request asked Graph for the object literally named 'False'.
#    A normalised boolean therefore must never appear inside an expandable string.
#
# These are checked against the entrypoint sources directly, so a new endpoint that
# reintroduces either pattern fails here rather than in production.

BeforeAll {
    $BackendRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
    $script:EntrypointRoot = Join-Path $BackendRoot 'Modules/CIPPHTTP/Public/Entrypoints/HTTP Functions'
    if (-not (Test-Path $script:EntrypointRoot)) { throw "Entrypoint root not found at $script:EntrypointRoot" }

    # Assignments of the shape  $X = $Request.Query.Foo -eq $true
    $script:NormalisedAssignment = [regex]::new('\$Request\.(Query|Body)\.\w+\s*-eq\s*\$(true|false)')

    $script:Parsed = @(
        foreach ($File in Get-ChildItem -Path $script:EntrypointRoot -Filter 'Invoke-*.ps1' -Recurse -File) {
            $Tokens = $null; $Errs = $null
            $Ast = [System.Management.Automation.Language.Parser]::ParseFile($File.FullName, [ref]$Tokens, [ref]$Errs)
            if ($Errs.Count -gt 0) { continue }
            [pscustomobject]@{
                Name = $File.Name
                Path = $File.FullName
                Ast  = $Ast
            }
        }
    )

    function Get-NormalisedBoolVar {
        # Variable names in this file that were assigned from a boolean normalisation.
        param($Ast)
        $Vars = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
        foreach ($Assign in $Ast.FindAll({ param($n) $n -is [System.Management.Automation.Language.AssignmentStatementAst] }, $true)) {
            if ($Assign.Left -isnot [System.Management.Automation.Language.VariableExpressionAst]) { continue }
            if ($script:NormalisedAssignment.IsMatch($Assign.Right.Extent.Text)) {
                $null = $Vars.Add($Assign.Left.VariablePath.UserPath)
            }
        }
        return $Vars
    }
}

Describe 'HTTP entrypoint boolean flags' {

    It 'has entrypoints to inspect' {
        $script:Parsed.Count | Should -BeGreaterThan 100
    }

    It 'never compares a request field against the strings "true"/"false"' {
        # -eq 'true' works at runtime but types the field as a string in openapi.json,
        # which ships a mistyped MCP tool. Use -eq $true instead.
        $StringCompare = [regex]::new("\`$[Rr]equest\.(Query|Body)\.\w+\s*-(eq|ne)\s*'(true|false)'", 'IgnoreCase')
        $Offenders = foreach ($Entry in $script:Parsed) {
            $Text = [System.IO.File]::ReadAllText($Entry.Path)
            foreach ($M in $StringCompare.Matches($Text)) {
                $Line = ($Text.Substring(0, $M.Index) -split "`n").Count
                "$($Entry.Name):$Line  $($M.Value)"
            }
        }
        $Offenders = @($Offenders)
        $Offenders -join "`n" | Should -BeNullOrEmpty -Because "these must use -eq `$true so the generated spec types them as boolean:`n$($Offenders -join "`n")"
    }

    It 'never interpolates a normalised boolean into a string' {
        # $null renders as '' but $false renders as 'False', so a flag spliced into a
        # URL or filter silently corrupts it the moment the parameter is omitted.
        $Offenders = foreach ($Entry in $script:Parsed) {
            $BoolVars = Get-NormalisedBoolVar -Ast $Entry.Ast
            if ($BoolVars.Count -eq 0) { continue }

            foreach ($Str in $Entry.Ast.FindAll({ param($n) $n -is [System.Management.Automation.Language.ExpandableStringExpressionAst] }, $true)) {
                foreach ($Nested in $Str.NestedExpressions) {
                    foreach ($Var in $Nested.FindAll({ param($n) $n -is [System.Management.Automation.Language.VariableExpressionAst] }, $true)) {
                        if (-not $BoolVars.Contains($Var.VariablePath.UserPath)) { continue }

                        # An explicit conversion - $($Flag.ToString().ToLower()) - is deliberate
                        # and renders 'true'/'false', which is what REST APIs expect. Only a bare
                        # interpolation of the variable is the hazard.
                        $Parent = $Var.Parent
                        $IsExplicit = ($Parent -is [System.Management.Automation.Language.MemberExpressionAst] -and
                            [object]::ReferenceEquals($Parent.Expression, $Var))
                        if (-not $IsExplicit) {
                            $Snippet = ($Str.Extent.Text -replace '\s+', ' ')
                            "$($Entry.Name):$($Str.Extent.StartLineNumber)  `$$($Var.VariablePath.UserPath) in: $($Snippet.Substring(0, [Math]::Min(100, $Snippet.Length)))"
                        }
                    }
                }
            }
        }
        $Offenders = @($Offenders)
        $Offenders -join "`n" | Should -BeNullOrEmpty -Because "a normalised boolean renders as 'False' when the parameter is absent:`n$($Offenders -join "`n")"
    }
}
