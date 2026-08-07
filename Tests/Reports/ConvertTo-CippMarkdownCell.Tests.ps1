# Pester tests for ConvertTo-CippMarkdownCell
# Verifies that values interpolated into Markdown table rows cannot open extra columns.

BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
    # Resolve by name under Modules/ so the test survives the function moving between modules.
    $HelperPath = Get-ChildItem -Path (Join-Path $RepoRoot 'Modules') -Recurse -Filter 'ConvertTo-CippMarkdownCell.ps1' -File -ErrorAction SilentlyContinue |
        Select-Object -First 1 -ExpandProperty FullName
    if (-not $HelperPath) { throw 'Could not locate ConvertTo-CippMarkdownCell.ps1 under Modules/' }

    . $HelperPath
}

Describe 'ConvertTo-CippMarkdownCell' {
    Context 'Pipe escaping' {
        It 'escapes a pipe so it stays inside its cell' {
            ConvertTo-CippMarkdownCell -Value 'John Doe | Contoso' | Should -Be 'John Doe \| Contoso'
        }

        It 'escapes every pipe in the value' {
            ConvertTo-CippMarkdownCell -Value 'A|B|C' | Should -Be 'A\|B\|C'
        }

        It 'leaves a value without pipes untouched' {
            ConvertTo-CippMarkdownCell -Value 'Microsoft 365 Business Premium' | Should -Be 'Microsoft 365 Business Premium'
        }
    }

    Context 'Newline handling' {
        It 'collapses a newline that would split the row in two' {
            ConvertTo-CippMarkdownCell -Value "Line1`nLine2" | Should -Be 'Line1 Line2'
        }

        It 'collapses Windows line endings' {
            ConvertTo-CippMarkdownCell -Value "Line1`r`nLine2" | Should -Be 'Line1 Line2'
        }
    }

    Context 'Non-string input' {
        It 'renders $null as an empty cell rather than dropping the column' {
            ConvertTo-CippMarkdownCell -Value $null | Should -Be ''
        }

        It 'renders an empty string as an empty cell' {
            ConvertTo-CippMarkdownCell -Value '' | Should -Be ''
        }

        It 'converts numbers' {
            ConvertTo-CippMarkdownCell -Value 42 | Should -Be '42'
        }

        It 'trims surrounding whitespace' {
            ConvertTo-CippMarkdownCell -Value '  padded  ' | Should -Be 'padded'
        }
    }

    Context 'Pipeline and positional use' {
        It 'accepts a positional argument' {
            ConvertTo-CippMarkdownCell 'John Doe | Contoso' | Should -Be 'John Doe \| Contoso'
        }

        It 'accepts pipeline input for each item' {
            $Result = @('A|B', 'C|D') | ConvertTo-CippMarkdownCell
            $Result | Should -HaveCount 2
            $Result[0] | Should -Be 'A\|B'
            $Result[1] | Should -Be 'C\|D'
        }
    }

    Context 'Row construction' {
        It 'produces a row with exactly as many cells as the header declares' {
            $Header = '| User | Licenses |'
            $Row = "| $(ConvertTo-CippMarkdownCell 'John Doe | Contoso') | $(ConvertTo-CippMarkdownCell 'E3, E5') |"

            # Count only the delimiters a Markdown parser would honour: pipes not preceded by a backslash.
            $CountDelimiters = {
                param($Line)
                ([regex]::Matches($Line, '(?<!\\)\|')).Count
            }

            & $CountDelimiters $Row | Should -Be (& $CountDelimiters $Header)
        }
    }
}
