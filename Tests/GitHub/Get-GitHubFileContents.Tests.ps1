# The contents API omits the body for files over 1 MB (encoding 'none'); those must be read from the blob.

BeforeAll {
    $BackendRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
    . (Join-Path $BackendRoot 'Modules/CippExtensions/Public/GitHub/Get-GitHubFileContents.ps1')
    function Invoke-GitHubApiRequest { param($Path, $Method) }
    $Json = '{"displayName":"Large CA template"}'
    $Base64 = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($Json))
}

Describe 'Get-GitHubFileContents' {
    It 'decodes inline content for files under 1 MB' {
        Mock Invoke-GitHubApiRequest { [PSCustomObject]@{ name = 'a.json'; path = 'a.json'; sha = 'abc'; size = 10; encoding = 'base64'; content = $Base64 } }

        $File = Get-GitHubFileContents -FullName 'o/r' -Path 'a.json' -Branch 'main'

        $File.content | Should -Be $Json
        Should -Invoke Invoke-GitHubApiRequest -Times 1 -Exactly
    }

    It 'reads the blob when the contents API omits a file over 1 MB' {
        Mock Invoke-GitHubApiRequest -ParameterFilter { $Path -like 'repos/o/r/contents/*' } { [PSCustomObject]@{ name = 'big.json'; path = 'big.json'; sha = 'def'; size = 1468271; encoding = 'none'; content = '' } }
        Mock Invoke-GitHubApiRequest -ParameterFilter { $Path -eq 'repos/o/r/git/blobs/def' } { [PSCustomObject]@{ sha = 'def'; size = 1468271; encoding = 'base64'; content = $Base64 } }

        $File = Get-GitHubFileContents -FullName 'o/r' -Path 'big.json' -Branch 'main'

        $File.content | Should -Be $Json
        $File.sha | Should -Be 'def'
        $File.size | Should -Be 1468271
    }
}
