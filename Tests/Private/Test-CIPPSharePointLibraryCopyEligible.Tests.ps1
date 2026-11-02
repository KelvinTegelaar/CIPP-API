# Pester tests for Test-CIPPSharePointLibraryCopyEligible.ps1

BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
    $FunctionPath = Join-Path $RepoRoot 'Modules/CIPPCore/Public/Test-CIPPSharePointLibraryCopyEligible.ps1'
    if (-not (Test-Path $FunctionPath)) { throw "Could not locate $FunctionPath" }
    . $FunctionPath
}

Describe 'Test-CIPPSharePointLibraryCopyEligible' {
    It 'accepts a normal document library' {
        (Test-CIPPSharePointLibraryCopyEligible -Template 'documentLibrary' -Title 'HR Docs' -Name 'HRDocs').Eligible | Should -Be $true
    }

    It 'rejects Site Pages template' {
        (Test-CIPPSharePointLibraryCopyEligible -Template 'webPageLibrary' -Title 'Site Pages').Eligible | Should -Be $false
    }

    It 'rejects Site Assets by title' {
        (Test-CIPPSharePointLibraryCopyEligible -Template 'documentLibrary' -Title 'Site Assets').Eligible | Should -Be $false
    }

    It 'rejects SiteAssets internal name' {
        (Test-CIPPSharePointLibraryCopyEligible -Template 'documentLibrary' -Title 'Docs' -Name 'SiteAssets').Eligible | Should -Be $false
    }
}
