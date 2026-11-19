# Pester tests for Start-AppPackageCleanup: packages older than a day are handed to Remove-CIPPUnusedAppPackage,
# which keeps any a template still uses; newer ones may belong to a template still being created.

BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
    function New-CIPPAzStorageRequest { param($Service, $Resource, $QueryParams) }
    function Remove-CIPPUnusedAppPackage { param([string[]]$PackageIds) }
    . (Join-Path $RepoRoot 'Modules/CIPPCore/Public/Entrypoints/Timer Functions/Start-AppPackageCleanup.ps1')

    $script:Old = '11111111-1111-1111-1111-111111111111'
    $script:New = '22222222-2222-2222-2222-222222222222'
    function New-Blob { param($Name, $Age) [pscustomobject]@{ Name = $Name; Properties = @{ 'Last-Modified' = [DateTime]::UtcNow.Add(-$Age).ToString('R') } } }
}

Describe 'Start-AppPackageCleanup' {
    It 'offers each package older than a day once, and none newer' {
        Mock New-CIPPAzStorageRequest {
            New-Blob "$script:Old/IntunePackage.intunewin" ([TimeSpan]::FromDays(3))
            New-Blob "$script:Old/packaged.json" ([TimeSpan]::FromDays(3))
            New-Blob "$script:New/installer" ([TimeSpan]::FromHours(2))
        }
        Mock Remove-CIPPUnusedAppPackage { }

        Start-AppPackageCleanup

        Should -Invoke Remove-CIPPUnusedAppPackage -Times 1 -Exactly -ParameterFilter { ($PackageIds -join ',') -eq $script:Old }
    }

    It 'does nothing when there are no packages' {
        Mock New-CIPPAzStorageRequest { }
        Mock Remove-CIPPUnusedAppPackage { }

        Start-AppPackageCleanup

        Should -Invoke Remove-CIPPUnusedAppPackage -Times 0
    }
}
