# GHSA-w39h-8vjv-6qm5: a curly quote in a condition value must stay data once the callers compile the string.

BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
    . (Join-Path $RepoRoot 'Modules/CIPPCore/Public/Tools/ConvertTo-CIPPScriptBlockValue.ps1')
    . (Join-Path $RepoRoot 'Modules/CIPPCore/Public/Tools/Test-CIPPConditionFilter.ps1')

    function Invoke-Sentinel { $script:SentinelRan = $true; $true }

    function New-Condition {
        param($Property = 'DisplayName', $Operator = 'eq', $Value)
        [pscustomobject]@{
            Property = [pscustomobject]@{ label = $Property }
            Operator = [pscustomobject]@{ value = $Operator }
            Input    = [pscustomobject]@{ value = $Value }
        }
    }

    function Invoke-Filter {
        param($Condition, $Records)
        $String = Test-CIPPConditionFilter -Condition $Condition -WarningAction SilentlyContinue
        if ($null -eq $String) { return $null }
        , @(@($Records).Where([ScriptBlock]::Create($String)))
    }
}

Describe 'Test-CIPPConditionFilter' {
    BeforeEach { $script:SentinelRan = $false }

    It 'keeps a <Name> quote inside the literal instead of running the rest of the value' -ForEach @(
        @{ Name = 'ASCII'; Quote = [char]0x27 }
        @{ Name = 'U+2018'; Quote = [char]0x2018 }
        @{ Name = 'U+2019'; Quote = [char]0x2019 }
        @{ Name = 'U+201A'; Quote = [char]0x201A }
        @{ Name = 'U+201B'; Quote = [char]0x201B }
        @{ Name = 'U+201C'; Quote = [char]0x201C }
        @{ Name = 'U+201D'; Quote = [char]0x201D }
    ) {
        $Payload = "a$Quote -or (Invoke-Sentinel) -or ${Quote}b"
        $Records = @([pscustomobject]@{ DisplayName = 'x' }, [pscustomobject]@{ DisplayName = $Payload })

        $Hits = Invoke-Filter -Condition (New-Condition -Value $Payload) -Records $Records

        $script:SentinelRan | Should -BeFalse
        $Hits.Count | Should -Be 1
        $Hits[0].DisplayName | Should -Be $Payload
    }

    It 'tells a curly apostrophe apart from the ASCII one' {
        $Curly = "O$([char]0x2019)Brien"
        $Records = @([pscustomobject]@{ DisplayName = "O'Brien" }, [pscustomobject]@{ DisplayName = $Curly })

        $Hits = Invoke-Filter -Condition (New-Condition -Value $Curly) -Records $Records

        $Hits.Count | Should -Be 1
        $Hits[0].DisplayName | Should -Be $Curly
        Test-CIPPConditionFilter -Condition (New-Condition -Value $Curly) | Should -Be "`$(`$_.DisplayName) -eq 'O$([char]0x2019)$([char]0x2019)Brien'"
    }

    It 'keeps a newline inside the literal' {
        $Value = "first`nWrite-Host second"
        $Records = @([pscustomobject]@{ DisplayName = 'first' }, [pscustomobject]@{ DisplayName = $Value })

        $Hits = Invoke-Filter -Condition (New-Condition -Value $Value) -Records $Records

        $Hits.Count | Should -Be 1
        $Hits[0].DisplayName | Should -Be $Value
    }

    It 'escapes every element of an array value' {
        $Curly = "x$([char]0x2019) -or (Invoke-Sentinel) -or $([char]0x2019)y"
        $Records = @([pscustomobject]@{ Operation = 'Set-Mailbox' }, [pscustomobject]@{ Operation = $Curly }, [pscustomobject]@{ Operation = 'other' })

        $Hits = Invoke-Filter -Condition (New-Condition -Property 'Operation' -Operator 'in' -Value @('Set-Mailbox', $Curly)) -Records $Records

        $script:SentinelRan | Should -BeFalse
        $Hits.Count | Should -Be 2
        $Hits.Operation | Should -Not -Contain 'other'
    }

    It 'still refuses the characters on the denylist (<Value>)' -ForEach @(
        @{ Value = 'a$b' }
        @{ Value = 'a`b' }
        @{ Value = 'a;b' }
        @{ Value = 'a|b' }
        @{ Value = 'a{b}' }
    ) {
        Test-CIPPConditionFilter -Condition (New-Condition -Value $Value) -WarningAction SilentlyContinue | Should -BeNullOrEmpty
    }

    It 'refuses an operator or property that is not on the allowlist' {
        Test-CIPPConditionFilter -Condition (New-Condition -Operator 'join' -Value 'x') -WarningAction SilentlyContinue | Should -BeNullOrEmpty
        Test-CIPPConditionFilter -Condition (New-Condition -Property 'Name; Invoke-Sentinel' -Value 'x') -WarningAction SilentlyContinue | Should -BeNullOrEmpty
        Test-CIPPConditionFilter -Condition (New-Condition -Property 'Name)' -Value 'x') -WarningAction SilentlyContinue | Should -BeNullOrEmpty
        $script:SentinelRan | Should -BeFalse
    }

    It 'refuses the condition when the escaping does not hold, even before compiling it' {
        Mock ConvertTo-CIPPScriptBlockValue { $Value }
        $Payload = "a$([char]0x2019) -or (Invoke-Sentinel) -or $([char]0x2019)b"

        Test-CIPPConditionFilter -Condition (New-Condition -Value $Payload) -WarningAction SilentlyContinue | Should -BeNullOrEmpty
        Test-CIPPConditionFilter -Condition (New-Condition -Value "a' -or 1 -eq 1 -or 'b") -WarningAction SilentlyContinue | Should -BeNullOrEmpty
        $script:SentinelRan | Should -BeFalse
    }

    It 'passes a plain condition through unchanged' {
        Test-CIPPConditionFilter -Condition (New-Condition -Property 'Operation' -Operator 'EQ' -Value 'Set-Mailbox') | Should -Be '$($_.Operation) -eq ''Set-Mailbox'''
        Test-CIPPConditionFilter -Condition (New-Condition -Property 'ModifiedProperties.Name' -Operator 'in' -Value @('a', 'b')) | Should -Be '$($_.ModifiedProperties.Name) -in @(''a'', ''b'')'
        Test-CIPPConditionFilter -Condition (New-Condition -Operator 'like' -Value '*admin*') | Should -Be '$($_.DisplayName) -like ''*admin*'''
    }
}
