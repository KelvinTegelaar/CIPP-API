BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
    . (Join-Path $RepoRoot 'Modules/CIPPCore/Public/Get-CippSandboxData.ps1')
    . (Join-Path $RepoRoot 'Modules/CIPPCore/Public/Get-CippErrorStatusCode.ps1')

    function Get-CIPPTestData { param($TenantFilter, $Type, $Fields) }
}

Describe 'Get-CippSandboxData' {
    BeforeEach {
        Mock Get-CIPPTestData { [pscustomobject]@{ Type = $Type } }
    }

    It 'fetches each named literal type once, projected through the manifest' {
        $Data = Get-CippSandboxData -TenantFilter 't' -ScriptContent "Get-CIPPTestData -Type 'Users'; Get-CIPPTestData -Type:'Groups'; Get-CIPPTestData -Type 'Users'"
        @($Data.Keys | Sort-Object) | Should -Be @('Groups', 'Users')
        Should -Invoke Get-CIPPTestData -Times 2 -Exactly
        Should -Invoke Get-CIPPTestData -ParameterFilter { $Type -eq 'Users' -and $TenantFilter -eq 't' -and -not $Fields } -Times 1 -Exactly
    }

    It 'rejects <Name> with a 400 and reads nothing' -ForEach @(
        @{ Name = 'a missing type'; Script = 'Get-CIPPTestData' }
        @{ Name = 'a positional type'; Script = "Get-CIPPTestData 'Users'" }
        @{ Name = 'a dynamic type'; Script = "`$t = 'Users'; Get-CIPPTestData -Type `$t" }
        @{ Name = 'an empty type'; Script = "Get-CIPPTestData -Type ''" }
    ) {
        $Status = try { Get-CippSandboxData -TenantFilter 't' -ScriptContent $Script; 0 } catch { [int](Get-CippErrorStatusCode -ErrorRecord $_) }
        $Status | Should -Be 400
        Should -Invoke Get-CIPPTestData -Times 0 -Exactly
    }
}
