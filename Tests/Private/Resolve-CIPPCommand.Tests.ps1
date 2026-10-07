BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
    . (Join-Path $RepoRoot 'Modules/CIPPCore/Public/Tools/Resolve-CIPPCommand.ps1')

    $Modules = Join-Path $TestDrive 'Modules'
    $Built = New-Item -ItemType Directory -Path (Join-Path $Modules 'ProbeBuilt') -Force
    Set-Content -Path (Join-Path $Built 'ProbeBuilt.psm1') -Value 'function Get-ProbeBuiltThing { }'
    Set-Content -Path (Join-Path $Built 'ProbeBuilt.psd1') -Value "@{ RootModule = 'ProbeBuilt.psm1'; ModuleVersion = '1.0'; FunctionsToExport = @('Get-ProbeBuiltThing') }"

    $Source = New-Item -ItemType Directory -Path (Join-Path $Modules 'ProbeSource/Public/Nested') -Force
    Set-Content -Path (Join-Path $Source 'Get-ProbeSourceThing.ps1') -Value 'function Get-ProbeSourceThing { }'
    Set-Content -Path (Join-Path $Modules 'ProbeSource/ProbeSource.psd1') -Value "@{ ModuleVersion = '1.0'; FunctionsToExport = '*' }"

    function Get-ProbeLoadedThing { }

    $script:OriginalRoot = $env:CIPPRootPath
    $script:OriginalModulePath = $env:PSModulePath
    $env:CIPPRootPath = $TestDrive
    $env:PSModulePath = $Modules + [System.IO.Path]::PathSeparator + $env:PSModulePath
}

AfterAll {
    $env:CIPPRootPath = $script:OriginalRoot
    $env:PSModulePath = $script:OriginalModulePath
}

Describe 'Resolve-CIPPCommand' {
    BeforeEach { $script:CIPPCommandIndex = $null }

    It 'resolves a built module export to its exact name without importing the module' {
        $Resolved = Resolve-CIPPCommand -Name 'get-probebuiltthing'

        $Resolved.Name | Should -BeExactly 'Get-ProbeBuiltThing'
        $Resolved.ModuleName | Should -Be 'ProbeBuilt'
        Get-Module -Name 'ProbeBuilt' | Should -BeNullOrEmpty
    }

    It 'falls back to Public file names for a wildcard source manifest' {
        (Resolve-CIPPCommand -Name 'Get-ProbeSourceThing').ModuleName | Should -Be 'ProbeSource'
    }

    It 'prefers a function that is already loaded' {
        (Resolve-CIPPCommand -Name 'get-probeloadedthing').Name | Should -BeExactly 'Get-ProbeLoadedThing'
    }

    It 'returns nothing for an unknown command' {
        Resolve-CIPPCommand -Name 'Get-ProbeMissingThing' | Should -BeNullOrEmpty
    }
}
