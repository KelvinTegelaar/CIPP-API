# GHSA-w39h-8vjv-6qm5: a curly quote in a dynamic group rule value must stay data once the string is compiled.

BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
    . (Join-Path $RepoRoot 'Modules/CIPPCore/Public/Tools/ConvertTo-CIPPScriptBlockValue.ps1')
    . (Join-Path $RepoRoot 'Modules/CIPPCore/Public/TenantGroups/Test-CIPPDynamicGroupFilter.ps1')

    function New-Tenant {
        param($Id, $Env, $Status = 'granularDelegatedAdminPrivileges')
        [pscustomobject]@{
            customerId               = $Id
            delegatedPrivilegeStatus = $Status
            customVariables          = @{ Env = [pscustomobject]@{ Value = $Env } }
        }
    }

    function Invoke-Rule {
        param($Rule, $Tenants)
        $String = Test-CIPPDynamicGroupFilter -Rule $Rule -WarningAction SilentlyContinue
        if ($null -eq $String) { return $null }
        , @(@($Tenants) | Where-Object ([ScriptBlock]::Create($String)))
    }
}

Describe 'Test-CIPPDynamicGroupFilter' {
    It 'keeps a <Name> quote in a custom variable value inside the literal' -ForEach @(
        @{ Name = 'ASCII'; Quote = [char]0x27 }
        @{ Name = 'U+2018'; Quote = [char]0x2018 }
        @{ Name = 'U+2019'; Quote = [char]0x2019 }
        @{ Name = 'U+201A'; Quote = [char]0x201A }
        @{ Name = 'U+201B'; Quote = [char]0x201B }
    ) {
        $Payload = "a$Quote -or 1 -eq 1 -or ${Quote}b"
        $Rule = [pscustomobject]@{ property = 'customVariable'; operator = 'eq'; value = [pscustomobject]@{ variableName = 'Env'; value = $Payload } }
        $Tenants = @((New-Tenant -Id 'c1' -Env 'prod'), (New-Tenant -Id 'c2' -Env $Payload))

        $Hits = Invoke-Rule -Rule $Rule -Tenants $Tenants

        $Hits.customerId | Should -Be @('c2')
    }

    It 'keeps a curly quote in a delegated access status value inside the literal' {
        $Payload = "a$([char]0x2019) -or 1 -eq 1 -or $([char]0x2019)b"
        $Rule = [pscustomobject]@{ property = 'delegatedAccessStatus'; operator = 'eq'; value = [pscustomobject]@{ value = $Payload } }
        $Tenants = @((New-Tenant -Id 'c1'), (New-Tenant -Id 'c2' -Status $Payload))

        $Hits = Invoke-Rule -Rule $Rule -Tenants $Tenants

        $Hits.customerId | Should -Be @('c2')
    }

    It 'still refuses values with denylisted characters' {
        $Rule = [pscustomobject]@{ property = 'customVariable'; operator = 'eq'; value = [pscustomobject]@{ variableName = 'Env'; value = 'a$(1)' } }
        Test-CIPPDynamicGroupFilter -Rule $Rule -WarningAction SilentlyContinue | Should -BeNullOrEmpty
    }

    It 'matches a plain value with an apostrophe' {
        $Rule = [pscustomobject]@{ property = 'customVariable'; operator = 'like'; value = [pscustomobject]@{ variableName = 'Env'; value = "O'Brien" } }
        $Tenants = @((New-Tenant -Id 'c1' -Env "O'Brien Ltd"), (New-Tenant -Id 'c2' -Env 'Other'))

        (Invoke-Rule -Rule $Rule -Tenants $Tenants).customerId | Should -Be @('c1')
    }
}
