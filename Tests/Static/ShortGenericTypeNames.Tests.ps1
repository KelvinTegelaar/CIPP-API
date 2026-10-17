# Function files are compiled into one module without their own `using namespace`, so a short
# [List[string]] only fails at runtime. Generic collection types must be fully qualified.

BeforeAll {
    $BackendRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
    $script:ModulesRoot = Join-Path $BackendRoot 'Modules'
    $script:Vendored = 'MicrosoftTeams|AzBobbyTables|DNSHealth|HuduAPI'
}

Describe 'Generic collection type names' {
    It 'are fully qualified in CIPP-owned modules' {
        $Files = Get-ChildItem -Path $script:ModulesRoot -Include '*.ps1', '*.psm1' -File -Recurse |
            Where-Object { $_.FullName -notmatch "[\\/]($script:Vendored)[\\/]" }
        $Files.Count | Should -BeGreaterThan 400

        $Offenders = foreach ($File in $Files) {
            $Ast = [System.Management.Automation.Language.Parser]::ParseFile($File.FullName, [ref]$null, [ref]$null)
            $Types = $Ast.FindAll({
                    $args[0] -is [System.Management.Automation.Language.TypeExpressionAst] -and
                    $args[0].TypeName -is [System.Management.Automation.Language.GenericTypeName] -and
                    $args[0].TypeName.TypeName.Name -match '^(List|Dictionary|HashSet|Queue|Stack|SortedSet|SortedDictionary|KeyValuePair)$'
                }, $true)
            foreach ($Type in $Types) { "$($File.Name):$($Type.Extent.StartLineNumber) $($Type.Extent.Text)" }
        }
        $Offenders | Should -BeNullOrEmpty
    }
}
