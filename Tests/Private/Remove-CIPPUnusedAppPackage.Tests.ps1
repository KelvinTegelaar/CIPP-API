# Pester tests for Remove-CIPPUnusedAppPackage: a package is deleted only once no app template references it.

BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
    function Get-CIPPTable { param($TableName) @{} }
    function Get-CIPPAzDataTableEntity { param($Filter) }
    function Get-CIPPAppPackageStorage { param($PackageId) [pscustomobject]@{ ConnectionString = 'UseDevelopmentStorage=true'; Custom = $false; LimitBytes = 0 } }
    function New-CIPPAzStorageRequest { param($Service, $ConnectionString, $Resource, $Method) }
    function Remove-CIPPAzDataTableEntity { param($Entity, [switch]$Force) }
    . (Join-Path $RepoRoot 'Modules/CIPPCore/Public/Remove-CIPPUnusedAppPackage.ps1')
}

Describe 'Remove-CIPPUnusedAppPackage' {
    BeforeEach {
        Mock New-CIPPAzStorageRequest { }
        Mock Get-CIPPAppPackageStorage { [pscustomobject]@{ ConnectionString = 'UseDevelopmentStorage=true'; Custom = $false; LimitBytes = 0 } }
        # Template configs are stored as JSON strings inside the template JSON, so the id appears escaped.
        Mock Get-CIPPAzDataTableEntity { [pscustomobject]@{ JSON = '{"Apps":[{"config":"{\"packageId\":\"still-used\"}"}]}' } }
    }

    It 'deletes every blob of a package no template uses' {
        Remove-CIPPUnusedAppPackage -PackageIds @('orphaned')

        foreach ($Blob in 'IntunePackage.intunewin', 'metadata.json', 'installer', 'packaged.json') {
            Should -Invoke New-CIPPAzStorageRequest -Times 1 -Exactly -ParameterFilter { $Method -eq 'DELETE' -and $Resource -eq "app-packages/orphaned/$Blob" }
        }
    }

    It 'deletes a package from the connected account it was uploaded to, and forgets where it was' {
        Mock Get-CIPPAppPackageStorage { [pscustomobject]@{ ConnectionString = 'theirs'; Custom = $true; AccountName = 'mine'; LimitBytes = 0 } }
        Mock Remove-CIPPAzDataTableEntity { }

        Remove-CIPPUnusedAppPackage -PackageIds @('orphaned')

        Should -Invoke New-CIPPAzStorageRequest -Times 4 -Exactly -ParameterFilter { $Method -eq 'DELETE' -and $ConnectionString -eq 'theirs' }
        Should -Invoke Remove-CIPPAzDataTableEntity -Times 1 -Exactly -ParameterFilter { $Entity.RowKey -eq 'orphaned' }
    }

    It 'skips a package whose account is no longer connected and carries on with the rest' {
        Mock Get-CIPPAppPackageStorage { throw 'no longer connected' } -ParameterFilter { $PackageId -eq 'stranded' }

        Remove-CIPPUnusedAppPackage -PackageIds @('stranded', 'orphaned')

        Should -Invoke New-CIPPAzStorageRequest -Times 0 -ParameterFilter { $Resource -like 'app-packages/stranded/*' }
        Should -Invoke New-CIPPAzStorageRequest -Times 4 -Exactly -ParameterFilter { $Resource -like 'app-packages/orphaned/*' }
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
