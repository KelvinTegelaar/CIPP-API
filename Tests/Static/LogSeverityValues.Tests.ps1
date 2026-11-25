# Log notifications filter with "Severity eq '<value>'", and table string comparison is case-sensitive,
# so a row logged as 'CRITICAL' or 'error' never reaches a technician who asked for Critical or Error alerts.

BeforeAll {
    $BackendRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
    $script:ModulesRoot = Join-Path $BackendRoot 'Modules'
    $script:Vendored = 'MicrosoftTeams|AzBobbyTables|DNSHealth|HuduAPI'
    $script:Allowed = [System.Collections.Generic.HashSet[string]]::new([string[]]@('Info', 'Warning', 'Error', 'Critical', 'Alert', 'Debug'), [System.StringComparer]::Ordinal)
}

Describe 'Write-LogMessage severity' {
    It 'is one of the exact values the notification filter matches' {
        $Checked = 0
        $Offenders = foreach ($File in Get-ChildItem -Path $script:ModulesRoot -Include '*.ps1', '*.psm1' -File -Recurse) {
            if ($File.FullName -match "[\\/]($script:Vendored)[\\/]") { continue }
            $Ast = [System.Management.Automation.Language.Parser]::ParseFile($File.FullName, [ref]$null, [ref]$null)
            foreach ($Call in $Ast.FindAll({ $args[0] -is [System.Management.Automation.Language.CommandAst] -and $args[0].GetCommandName() -eq 'Write-LogMessage' }, $true)) {
                $Elements = $Call.CommandElements
                for ($i = 1; $i -lt $Elements.Count; $i++) {
                    if ($Elements[$i] -isnot [System.Management.Automation.Language.CommandParameterAst] -or $Elements[$i].ParameterName -ne 'sev') { continue }
                    $Value = $Elements[$i].Argument ?? $Elements[$i + 1]
                    # Only literals can be checked statically; variables are left to the caller.
                    if ($Value -isnot [System.Management.Automation.Language.StringConstantExpressionAst]) { continue }
                    $Checked++
                    if (-not $script:Allowed.Contains($Value.Value)) { "$($File.Name):$($Value.Extent.StartLineNumber) -sev '$($Value.Value)'" }
                }
            }
        }
        $Checked | Should -BeGreaterThan 3000
        $Offenders | Should -BeNullOrEmpty
    }
}
