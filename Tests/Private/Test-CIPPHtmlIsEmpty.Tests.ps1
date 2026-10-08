# Pester tests for Test-CIPPHtmlIsEmpty — TipTap empty docs must not count as content.

BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
    $FunctionPath = Join-Path $RepoRoot 'Modules/CIPPCore/Public/Test-CIPPHtmlIsEmpty.ps1'
    if (-not (Test-Path $FunctionPath)) { throw "Could not locate Test-CIPPHtmlIsEmpty.ps1 at $FunctionPath" }
    . $FunctionPath
}

Describe 'Test-CIPPHtmlIsEmpty' {
    It 'treats null and whitespace as empty' {
        Test-CIPPHtmlIsEmpty -Html $null | Should -BeTrue
        Test-CIPPHtmlIsEmpty -Html '' | Should -BeTrue
        Test-CIPPHtmlIsEmpty -Html '   ' | Should -BeTrue
    }

    It 'treats TipTap placeholder markup as empty' {
        Test-CIPPHtmlIsEmpty -Html '<p></p>' | Should -BeTrue
        Test-CIPPHtmlIsEmpty -Html '<p><br></p>' | Should -BeTrue
        Test-CIPPHtmlIsEmpty -Html '<p><br/></p>' | Should -BeTrue
        Test-CIPPHtmlIsEmpty -Html '<p>&nbsp;</p>' | Should -BeTrue
    }

    It 'treats real message HTML as not empty' {
        Test-CIPPHtmlIsEmpty -Html '<p>This mailbox is no longer monitored at %tenantname%.</p>' | Should -BeFalse
    }
}
