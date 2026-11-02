# A call from CIPPCore/CIPPHTTP would autoload CIPPBaselines into HTTP workers; endpoint-reachable baseline code stays in CIPPCore.

BeforeAll {
    $BackendRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
    $ModulesRoot = Join-Path $BackendRoot 'Modules'

    $script:BaselineFunctions = @((Get-ChildItem -Path (Join-Path $ModulesRoot 'CIPPBaselines/Public') -Filter '*.ps1' -File -Recurse).BaseName)
    if ($script:BaselineFunctions.Count -lt 100) { throw "Expected the CIPPBaselines source set to be present; found $($script:BaselineFunctions.Count) files" }

    $script:Sources = foreach ($Module in 'CIPPCore', 'CIPPHTTP') {
        foreach ($File in (Get-ChildItem -Path (Join-Path $ModulesRoot $Module) -Filter '*.ps1' -File -Recurse)) {
            $Text = [System.IO.File]::ReadAllText($File.FullName)
            $Text = [regex]::Replace($Text, '<#[\s\S]*?#>', '')
            [pscustomobject]@{ Name = "$Module/$($File.Name)"; Text = [regex]::Replace($Text, '(?m)#.*$', '') }
        }
    }
}

Describe 'CIPPBaselines module boundary' {
    It 'is not referenced from CIPPCore or CIPPHTTP' {
        $Pattern = [regex]('(?<![\w-])(' + (($script:BaselineFunctions | ForEach-Object { [regex]::Escape($_) }) -join '|') + ')(?![\w-])')
        $Offenders = @(foreach ($Source in $script:Sources) {
                foreach ($Match in $Pattern.Matches($Source.Text)) { "$($Source.Name) -> $($Match.Value)" }
            })
        $Offenders | Should -BeNullOrEmpty -Because 'HTTP workers must not autoload CIPPBaselines; keep endpoint-reachable baseline functions in CIPPCore'
    }
}
