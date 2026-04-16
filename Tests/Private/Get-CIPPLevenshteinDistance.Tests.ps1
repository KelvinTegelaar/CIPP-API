# Pester tests for Get-CIPPLevenshteinDistance
# Verifies correctness of the Wagner-Fischer dynamic-programming implementation,
# edge-case handling, case sensitivity, normalisation mode, and return types.

BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
    $FunctionPath = Join-Path $RepoRoot 'Modules/CIPPCore/Public/Tools/Get-CIPPLevenshteinDistance.ps1'
    if (-not (Test-Path -Path $FunctionPath)) {
        $FunctionPath = Join-Path $RepoRoot 'Modules/CIPPCore/Private/Get-CIPPLevenshteinDistance.ps1'
    }
    . $FunctionPath
}

Describe 'Get-CIPPLevenshteinDistance' {

    Context 'Classic well-known examples' {
        It 'returns 3 for kitten -> sitting' {
            Get-CIPPLevenshteinDistance -Source 'kitten' -Target 'sitting' | Should -Be 3
        }

        It 'returns 3 for saturday -> sunday' {
            Get-CIPPLevenshteinDistance -Source 'saturday' -Target 'sunday' | Should -Be 3
        }

        It 'returns 5 for intention -> execution' {
            Get-CIPPLevenshteinDistance -Source 'intention' -Target 'execution' | Should -Be 5
        }

        It 'returns 2 for flaw -> lawn' {
            Get-CIPPLevenshteinDistance -Source 'flaw' -Target 'lawn' | Should -Be 2
        }
    }

    Context 'Identical strings' {
        It 'returns 0 for identical single-word strings' {
            Get-CIPPLevenshteinDistance -Source 'abc' -Target 'abc' | Should -Be 0
        }

        It 'returns 0 for identical single characters' {
            Get-CIPPLevenshteinDistance -Source 'z' -Target 'z' | Should -Be 0
        }

        It 'returns 0 for identical multi-word strings' {
            Get-CIPPLevenshteinDistance -Source 'hello world' -Target 'hello world' | Should -Be 0
        }
    }

    Context 'Empty string edge cases' {
        It 'returns target length when source is empty' {
            Get-CIPPLevenshteinDistance -Source '' -Target 'hello' | Should -Be 5
        }

        It 'returns source length when target is empty' {
            Get-CIPPLevenshteinDistance -Source 'hello' -Target '' | Should -Be 5
        }

        It 'returns 0 when both strings are empty' {
            Get-CIPPLevenshteinDistance -Source '' -Target '' | Should -Be 0
        }

        It 'returns 1 for single char vs empty' {
            Get-CIPPLevenshteinDistance -Source 'a' -Target '' | Should -Be 1
        }

        It 'returns 1 for empty vs single char' {
            Get-CIPPLevenshteinDistance -Source '' -Target 'a' | Should -Be 1
        }
    }

    Context 'Single character operations' {
        It 'returns 1 for a substitution between two different single chars' {
            Get-CIPPLevenshteinDistance -Source 'a' -Target 'b' | Should -Be 1
        }

        It 'returns 1 for a single insertion (a -> ab)' {
            Get-CIPPLevenshteinDistance -Source 'a' -Target 'ab' | Should -Be 1
        }

        It 'returns 1 for a single deletion (ab -> a)' {
            Get-CIPPLevenshteinDistance -Source 'ab' -Target 'a' | Should -Be 1
        }
    }

    Context 'Case sensitivity - default (insensitive)' {
        It 'returns 0 for strings that differ only in case' {
            Get-CIPPLevenshteinDistance -Source 'ABC' -Target 'abc' | Should -Be 0
        }

        It 'returns 0 for mixed-case identical strings' {
            Get-CIPPLevenshteinDistance -Source 'Hello' -Target 'hello' | Should -Be 0
        }

        It 'returns correct distance ignoring case (Kitten vs SITTING = 3)' {
            Get-CIPPLevenshteinDistance -Source 'Kitten' -Target 'SITTING' | Should -Be 3
        }
    }

    Context 'Case sensitivity - CaseSensitive switch' {
        It 'returns 3 for ABC vs abc when case-sensitive' {
            Get-CIPPLevenshteinDistance -Source 'ABC' -Target 'abc' -CaseSensitive | Should -Be 3
        }

        It 'returns 0 for identical strings when case-sensitive' {
            Get-CIPPLevenshteinDistance -Source 'Hello' -Target 'Hello' -CaseSensitive | Should -Be 0
        }

        It 'returns non-zero for same letters in different case when case-sensitive' {
            Get-CIPPLevenshteinDistance -Source 'Hello' -Target 'hello' -CaseSensitive | Should -BeGreaterThan 0
        }

        It 'returns same result as default for all-lowercase inputs' {
            $cs = Get-CIPPLevenshteinDistance -Source 'kitten' -Target 'sitting' -CaseSensitive
            $ci = Get-CIPPLevenshteinDistance -Source 'kitten' -Target 'sitting'
            $cs | Should -Be $ci
        }
    }

    Context 'Symmetry property' {
        It 'produces the same distance regardless of argument order (kitten/sitting)' {
            $fwd = Get-CIPPLevenshteinDistance -Source 'kitten' -Target 'sitting'
            $rev = Get-CIPPLevenshteinDistance -Source 'sitting' -Target 'kitten'
            $fwd | Should -Be $rev
        }

        It 'produces the same distance regardless of argument order (abc/xyz)' {
            $fwd = Get-CIPPLevenshteinDistance -Source 'abc' -Target 'xyz'
            $rev = Get-CIPPLevenshteinDistance -Source 'xyz' -Target 'abc'
            $fwd | Should -Be $rev
        }
    }

    Context 'Normalize switch' {
        It 'returns 0.0 for identical strings' {
            $result = Get-CIPPLevenshteinDistance -Source 'abc' -Target 'abc' -Normalize
            $result | Should -Be 0.0
        }

        It 'returns 0.0 for both-empty strings' {
            $result = Get-CIPPLevenshteinDistance -Source '' -Target '' -Normalize
            $result | Should -Be ([double]0)
        }

        It 'returns 1.0 when source is empty and target is non-empty' {
            $result = Get-CIPPLevenshteinDistance -Source '' -Target 'hello' -Normalize
            $result | Should -Be 1.0
        }

        It 'returns 1.0 when target is empty and source is non-empty' {
            $result = Get-CIPPLevenshteinDistance -Source 'hello' -Target '' -Normalize
            $result | Should -Be 1.0
        }

        It 'returns ~0.4286 for kitten -> sitting (3/7)' {
            $result = Get-CIPPLevenshteinDistance -Source 'kitten' -Target 'sitting' -Normalize
            $result | Should -BeGreaterThan 0.428
            $result | Should -BeLessThan 0.429
        }

        It 'returns 0.375 for saturday -> sunday (3/8)' {
            $result = Get-CIPPLevenshteinDistance -Source 'saturday' -Target 'sunday' -Normalize
            $result | Should -Be 0.375
        }

        It 'divides by the longer string length, not source length' {
            # Source is 1 char, target is 5 chars; distance = 5; max = 5 → 1.0
            $result = Get-CIPPLevenshteinDistance -Source 'x' -Target 'hello' -Normalize
            $result | Should -Be 1.0
        }
    }

    Context 'Return types' {
        It 'returns an integer without -Normalize' {
            $result = Get-CIPPLevenshteinDistance -Source 'kitten' -Target 'sitting'
            $result | Should -BeOfType [int]
        }

        It 'returns a double with -Normalize' {
            $result = Get-CIPPLevenshteinDistance -Source 'kitten' -Target 'sitting' -Normalize
            $result | Should -BeOfType [double]
        }

        It 'returns a double (0.0) for identical strings with -Normalize' {
            $result = Get-CIPPLevenshteinDistance -Source 'abc' -Target 'abc' -Normalize
            $result | Should -BeOfType [double]
        }
    }
}
