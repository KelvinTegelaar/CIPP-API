# Pester tests for Get-CIPPAppPackageFile: package files in the instance storage and the connected account.

BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
    function Get-CIPPAppPackageStorage { }
    function New-CIPPAzStorageRequest { [CmdletBinding()] param($Service, $ConnectionString, $Resource, $QueryParams) }
    . (Join-Path $RepoRoot 'Modules/CIPPCore/Public/Get-CIPPAppPackageFile.ps1')
    $script:SavedStorage = $env:AzureWebJobsStorage
    $env:AzureWebJobsStorage = 'own'
    function New-Blob { param($Name, $Size) [pscustomobject]@{ Name = $Name; Properties = @{ 'Content-Length' = "$Size"; 'Last-Modified' = 'Mon, 23 Nov 2026 10:00:00 GMT' } } }
}

AfterAll { $env:AzureWebJobsStorage = $script:SavedStorage }

Describe 'Get-CIPPAppPackageFile' {
    It 'lists the instance storage and the connected account, marking which is which' {
        Mock Get-CIPPAppPackageStorage { [pscustomobject]@{ ConnectionString = 'theirs'; Custom = $true } }
        Mock New-CIPPAzStorageRequest { if ($ConnectionString -eq 'own') { New-Blob 'a/IntunePackage.intunewin' 10 } else { New-Blob 'b/IntunePackage.intunewin' 20 } }

        $Files = @(Get-CIPPAppPackageFile)

        $Files.Count | Should -Be 2
        $Files.Where({ $_.PackageId -eq 'a' })[0].Custom | Should -BeFalse
        $Files.Where({ $_.PackageId -eq 'b' })[0].Custom | Should -BeTrue
        $Files.Where({ $_.PackageId -eq 'b' })[0].Size | Should -Be 20
        Should -Invoke New-CIPPAzStorageRequest -Times 2 -Exactly
    }

    It 'lists only the instance storage when no account is connected' {
        Mock Get-CIPPAppPackageStorage { [pscustomobject]@{ ConnectionString = 'own'; Custom = $false } }
        Mock New-CIPPAzStorageRequest { New-Blob 'a/metadata.json' 5 }

        @(Get-CIPPAppPackageFile).Count | Should -Be 1
        Should -Invoke New-CIPPAzStorageRequest -Times 1 -Exactly -ParameterFilter { $ConnectionString -eq 'own' }
    }

    It 'treats a missing container as no packages, and reports any other failure' {
        Mock Get-CIPPAppPackageStorage { [pscustomobject]@{ ConnectionString = 'own'; Custom = $false } }
        Mock New-CIPPAzStorageRequest { Write-Error 'Status 404 <Code>ContainerNotFound</Code>' }
        @(Get-CIPPAppPackageFile -ErrorAction Stop).Count | Should -Be 0

        Mock New-CIPPAzStorageRequest { Write-Error 'Status 403 AuthorizationFailure' }
        { Get-CIPPAppPackageFile -ErrorAction Stop } | Should -Throw '*403*'
    }
}
