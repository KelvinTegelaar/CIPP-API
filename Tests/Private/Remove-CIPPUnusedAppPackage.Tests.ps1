# Pester tests for Remove-CIPPUnusedAppPackage: a package is deleted only once no app template references it.

BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
    function Get-CIPPTable { param($TableName) @{} }
    function Get-CIPPAzDataTableEntity { param($Filter) }
    function New-CIPPAzStorageRequest { param($Service, $Resource, $Method) }
    . (Join-Path $RepoRoot 'Modules/CIPPCore/Public/Remove-CIPPUnusedAppPackage.ps1')
}

Describe 'Remove-CIPPUnusedAppPackage' {
    BeforeEach {
        Mock New-CIPPAzStorageRequest { }
        # Template configs are stored as JSON strings inside the template JSON, so the id appears escaped.
        Mock Get-CIPPAzDataTableEntity { [pscustomobject]@{ JSON = '{"Apps":[{"config":"{\"packageId\":\"still-used\"}"}]}' } }
    }

    It 'deletes every blob of a package no template uses' {
        Remove-CIPPUnusedAppPackage -PackageIds @('orphaned')

        foreach ($Blob in 'IntunePackage.intunewin', 'metadata.json', 'installer', 'packaged.json') {
            Should -Invoke New-CIPPAzStorageRequest -Times 1 -Exactly -ParameterFilter { $Method -eq 'DELETE' -and $Resource -eq "app-packages/orphaned/$Blob" }
        }
    }

    It 'keeps a package another template still references' {
        Remove-CIPPUnusedAppPackage -PackageIds @('still-used')

        Should -Invoke New-CIPPAzStorageRequest -Times 0
    }

    It 'does nothing without package ids' {
        Remove-CIPPUnusedAppPackage -PackageIds $null

        Should -Invoke Get-CIPPAzDataTableEntity -Times 0
    }
}
