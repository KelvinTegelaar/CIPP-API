# Without a console host every Write-Host throws and swallows a HostException; Write-Information logs the same record.

BeforeAll {
    $BackendRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
    $script:ModulesRoot = Join-Path $BackendRoot 'Modules'
    $script:Vendored = 'MicrosoftTeams|AzBobbyTables|DNSHealth|HuduAPI'
}

Describe 'Write-Host' {
    It 'is not called in CIPP-owned modules' {
        $Files = Get-ChildItem -Path $script:ModulesRoot -Include '*.ps1', '*.psm1' -File -Recurse |
            Where-Object { $_.FullName -notmatch "[\\/]($script:Vendored)[\\/]" }
        $Files.Count | Should -BeGreaterThan 400

        $Offenders = foreach ($File in $Files) {
            $Ast = [System.Management.Automation.Language.Parser]::ParseFile($File.FullName, [ref]$null, [ref]$null)
            foreach ($Call in $Ast.FindAll({ $args[0] -is [System.Management.Automation.Language.CommandAst] -and $args[0].GetCommandName() -eq 'Write-Host' }, $true)) {
                "$($File.Name):$($Call.Extent.StartLineNumber)"
            }
        }
        $Offenders | Should -BeNullOrEmpty
    }
}
