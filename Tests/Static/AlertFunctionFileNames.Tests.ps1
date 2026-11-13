# Alert snoozes are stored under the cmdlet name that Resolve-CIPPCommand returns, which comes from the
# file name when CIPPAlerts is not loaded. Write-AlertTrace looks them up under the function's own name,
# and table keys are case-sensitive, so a file whose name differs from its function only in case breaks snoozing.

BeforeAll {
    $BackendRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
    $script:AlertFiles = @(Get-ChildItem -Path (Join-Path $BackendRoot 'Modules/CIPPAlerts/Public') -Filter '*.ps1' -File -Recurse)
}

Describe 'CIPPAlerts file names' {
    It 'finds the alert files' {
        $script:AlertFiles.Count | Should -BeGreaterThan 0
    }

    It 'names every file exactly after the function it defines, including case' {
        foreach ($File in $script:AlertFiles) {
            $Ast = [System.Management.Automation.Language.Parser]::ParseFile($File.FullName, [ref]$null, [ref]$null)
            $Function = $Ast.Find({ param($Node) $Node -is [System.Management.Automation.Language.FunctionDefinitionAst] }, $false)
            $Function | Should -Not -BeNullOrEmpty -Because "$($File.Name) should define a function"
            $Function.Name | Should -BeExactly $File.BaseName -Because "snooze keys for $($File.Name) must match the name Write-AlertTrace uses"
        }
    }
}
