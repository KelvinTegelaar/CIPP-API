# The frontend cannot guess a synced template's repo path - the scheduled sync matches files by
# sanitised filename anywhere in the tree, so the path is only known at import/push time and is
# stored as SourcePath. This builds the GitHub URL from Source/SourcePath plus the repo's branch.

BeforeAll {
    $BackendRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
    $FunctionPath = Join-Path $BackendRoot 'Modules/CIPPCore/Public/GitHub/Get-CIPPTemplateSourceUrl.ps1'

    function Get-CIPPTable { param($TableName) @{ Context = "stub-$TableName" } }
    function Get-CIPPAzDataTableEntity { param($Context, $Filter) }

    . $FunctionPath
}

Describe 'Get-CIPPTemplateSourceUrl' {
    It 'returns $null when Source is empty' {
        Get-CIPPTemplateSourceUrl -Source '' -SourcePath 'CATemplate/Foo.json' | Should -BeNullOrEmpty
    }

    It 'returns the repo root URL when SourcePath is not set' {
        Get-CIPPTemplateSourceUrl -Source 'Org/repo' -Repos @() | Should -Be 'https://github.com/Org/repo'
    }

    It 'returns a blob URL on the default branch when no repo row matches' {
        Get-CIPPTemplateSourceUrl -Source 'Org/repo' -SourcePath 'CATemplate/Foo.json' -Repos @() |
            Should -Be 'https://github.com/Org/repo/blob/main/CATemplate/Foo.json'
    }

    It 'uses the repo row UploadBranch over DefaultBranch' {
        $Repos = @([pscustomobject]@{ FullName = 'Org/repo'; UploadBranch = 'staging'; DefaultBranch = 'main' })
        Get-CIPPTemplateSourceUrl -Source 'Org/repo' -SourcePath 'CATemplate/Foo.json' -Repos $Repos |
            Should -Be 'https://github.com/Org/repo/blob/staging/CATemplate/Foo.json'
    }

    It 'falls back to DefaultBranch when UploadBranch is not set' {
        $Repos = @([pscustomobject]@{ FullName = 'Org/repo'; DefaultBranch = 'develop' })
        Get-CIPPTemplateSourceUrl -Source 'Org/repo' -SourcePath 'CATemplate/Foo.json' -Repos $Repos |
            Should -Be 'https://github.com/Org/repo/blob/develop/CATemplate/Foo.json'
    }

    It 'does one table read when -Repos is not pre-fetched' {
        Mock -CommandName Get-CIPPAzDataTableEntity -MockWith { @() }
        $null = Get-CIPPTemplateSourceUrl -Source 'Org/repo' -SourcePath 'CATemplate/Foo.json'
        Should -Invoke Get-CIPPAzDataTableEntity -Times 1
    }
}
