# Pester tests for Start-AppPackageCleanup: packages older than a day are handed to Remove-CIPPUnusedAppPackage,
# which keeps any a template still uses; newer ones may belong to a template still being created.

BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
    function Get-CIPPAppPackageFile { [CmdletBinding()] param() }
    function Remove-CIPPUnusedAppPackage { param([string[]]$PackageIds) }
    . (Join-Path $RepoRoot 'Modules/CIPPCore/Public/Entrypoints/Timer Functions/Start-AppPackageCleanup.ps1')

    $script:Old = '11111111-1111-1111-1111-111111111111'
    $script:New = '22222222-2222-2222-2222-222222222222'
    function New-File { param($Name, $Age, [switch]$Custom) [pscustomobject]@{ PackageId = $Name.Split('/')[0]; Name = $Name; LastModified = [DateTime]::UtcNow.Add(-$Age).ToString('R'); Custom = [bool]$Custom } }
    $script:Theirs = '33333333-3333-3333-3333-333333333333'
}

Describe 'Start-AppPackageCleanup' {
    It 'offers each package older than a day once, from either storage, and none newer' {
        Mock Get-CIPPAppPackageFile {
            New-File "$script:Old/IntunePackage.intunewin" ([TimeSpan]::FromDays(3))
            New-File "$script:Old/packaged.json" ([TimeSpan]::FromDays(3))
            New-File "$script:New/installer" ([TimeSpan]::FromHours(2))
            New-File "$script:Theirs/IntunePackage.intunewin" ([TimeSpan]::FromDays(2)) -Custom
        }
        Mock Remove-CIPPUnusedAppPackage { }

        Start-AppPackageCleanup

        Should -Invoke Remove-CIPPUnusedAppPackage -Times 1 -Exactly -ParameterFilter { ($PackageIds -join ',') -eq "$script:Old,$script:Theirs" }
    }

    It 'does nothing when there are no packages' {
        Mock Get-CIPPAppPackageFile { }
        Mock Remove-CIPPUnusedAppPackage { }

        Start-AppPackageCleanup

        Should -Invoke Remove-CIPPUnusedAppPackage -Times 0
    }
}
