# Pester tests for Test-CIPPSharePointLibraryCopyFolderName.ps1

BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
    $FunctionPath = Join-Path $RepoRoot 'Modules/CIPPCore/Public/Test-CIPPSharePointLibraryCopyFolderName.ps1'
    if (-not (Test-Path $FunctionPath)) { throw "Could not locate $FunctionPath" }
    . $FunctionPath
}

Describe 'Test-CIPPSharePointLibraryCopyFolderName' {
    It 'accepts a typical OneDrive archive folder name' {
        $Result = Test-CIPPSharePointLibraryCopyFolderName -FolderName 'Archive - jane@contoso.com'
        $Result.Valid | Should -Be $true
        $Result.Name | Should -Be 'Archive - jane@contoso.com'
    }

    It 'trims surrounding whitespace' {
        (Test-CIPPSharePointLibraryCopyFolderName -FolderName "  Archive 2026`t").Name | Should -Be 'Archive 2026'
    }

    It 'accepts names with dots that are not only dots' {
        (Test-CIPPSharePointLibraryCopyFolderName -FolderName 'j.doe.archive').Valid | Should -Be $true
    }

    It 'rejects illegal character <Char>' -ForEach @(
        @{ Char = '"' }
        @{ Char = '*' }
        @{ Char = ':' }
        @{ Char = '<' }
        @{ Char = '>' }
        @{ Char = '?' }
        @{ Char = '/' }
        @{ Char = '\' }
        @{ Char = '|' }
    ) {
        $Result = Test-CIPPSharePointLibraryCopyFolderName -FolderName "Archive${Char}jane"
        $Result.Valid | Should -Be $false
        $Result.Reason | Should -Not -BeNullOrEmpty
    }

    It 'rejects control characters' {
        (Test-CIPPSharePointLibraryCopyFolderName -FolderName "Archive`njane").Valid | Should -Be $false
    }

    It 'rejects empty, whitespace-only and dot-only names (<Name>)' -ForEach @(
        @{ Name = '' }
        @{ Name = '   ' }
        @{ Name = '.' }
        @{ Name = '..' }
        @{ Name = ' . . ' }
    ) {
        (Test-CIPPSharePointLibraryCopyFolderName -FolderName $Name).Valid | Should -Be $false
    }

    It 'rejects SharePoint reserved names case-insensitively (<Name>)' -ForEach @(
        @{ Name = 'Forms' }
        @{ Name = 'forms' }
        @{ Name = 'CON' }
        @{ Name = 'lpt1' }
        @{ Name = 'desktop.ini' }
    ) {
        (Test-CIPPSharePointLibraryCopyFolderName -FolderName $Name).Valid | Should -Be $false
    }

    It 'rejects ~$ prefixes and _vti_' {
        (Test-CIPPSharePointLibraryCopyFolderName -FolderName '~$archive').Valid | Should -Be $false
        (Test-CIPPSharePointLibraryCopyFolderName -FolderName 'my_vti_folder').Valid | Should -Be $false
    }

    It 'rejects names longer than 255 characters' {
        (Test-CIPPSharePointLibraryCopyFolderName -FolderName ('a' * 256)).Valid | Should -Be $false
        (Test-CIPPSharePointLibraryCopyFolderName -FolderName ('a' * 255)).Valid | Should -Be $true
    }
}
