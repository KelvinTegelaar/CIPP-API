# A named parameter that a function does not declare is silently dropped when the function has no
# [CmdletBinding()] (Write-LogMessage -Level Error logged with no severity), and throws at runtime when it does.

BeforeAll {
    $BackendRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
    $ModulesRoot = Join-Path $BackendRoot 'Modules'
    $Vendored = 'MicrosoftTeams|AzBobbyTables|DNSHealth|HuduAPI'
    # Inert on simple functions and valid on advanced ones, so never a silent drop worth failing on.
    [string[]]$Common = [System.Management.Automation.Cmdlet]::CommonParameters + [System.Management.Automation.Cmdlet]::OptionalCommonParameters + 'ProgressAction'

    $script:Asts = foreach ($File in Get-ChildItem -Path $ModulesRoot -Include '*.ps1', '*.psm1' -File -Recurse) {
        if ($File.FullName -match "[\\/]($Vendored)[\\/]") { continue }
        [pscustomobject]@{ Name = $File.Name; Ast = [System.Management.Automation.Language.Parser]::ParseFile($File.FullName, [ref]$null, [ref]$null) }
    }

    # Function name -> declared parameter names and aliases. $null marks a function with dynamic parameters.
    $script:Declared = @{}
    foreach ($Entry in $script:Asts) {
        foreach ($Fn in $Entry.Ast.FindAll({ $args[0] -is [System.Management.Automation.Language.FunctionDefinitionAst] }, $true)) {
            if ($Fn.Body.DynamicBlock -or ($script:Declared.ContainsKey($Fn.Name) -and $null -eq $script:Declared[$Fn.Name])) {
                $script:Declared[$Fn.Name] = $null
                continue
            }
            if (-not $script:Declared[$Fn.Name]) { $script:Declared[$Fn.Name] = [System.Collections.Generic.List[string]]::new($Common) }
            foreach ($Param in ($Fn.Body.ParamBlock ? $Fn.Body.ParamBlock.Parameters : $Fn.Parameters)) {
                $script:Declared[$Fn.Name].Add($Param.Name.VariablePath.UserPath)
                foreach ($Attr in $Param.Attributes) {
                    if ($Attr.TypeName.Name -eq 'Alias') { foreach ($Alias in $Attr.PositionalArguments) { $script:Declared[$Fn.Name].Add($Alias.SafeGetValue()) } }
                }
            }
        }
    }
}

Describe 'Calls to CIPP functions' {
    It 'only pass parameters the function declares' {
        $script:Declared.Count | Should -BeGreaterThan 1000

        $Offenders = foreach ($Entry in $script:Asts) {
            foreach ($Call in $Entry.Ast.FindAll({ $args[0] -is [System.Management.Automation.Language.CommandAst] }, $true)) {
                $Name = $Call.GetCommandName()
                if (-not $Name -or -not $script:Declared[$Name]) { continue }
                foreach ($Element in $Call.CommandElements) {
                    if ($Element -isnot [System.Management.Automation.Language.CommandParameterAst]) { continue }
                    $Matched = $false
                    foreach ($Known in $script:Declared[$Name]) {
                        if ($Known.StartsWith($Element.ParameterName, [System.StringComparison]::OrdinalIgnoreCase)) { $Matched = $true; break }
                    }
                    if (-not $Matched) { "$($Entry.Name):$($Element.Extent.StartLineNumber) $Name -$($Element.ParameterName)" }
                }
            }
        }
        $Offenders | Should -BeNullOrEmpty
    }
}
