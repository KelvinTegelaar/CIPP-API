BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
    . (Join-Path $RepoRoot 'Modules/CIPPCore/Public/Get-CippErrorStatusCode.ps1')

    function Get-CaughtStatus([scriptblock]$Thrower) {
        try { & $Thrower } catch { Get-CippErrorStatusCode -ErrorRecord $_ }
    }
}

Describe 'Get-CippErrorStatusCode' {
    It 'maps a typed ArgumentException thrown by a helper to 400' {
        Get-CaughtStatus { throw [System.ArgumentException]::new('SiteUrl is required.') } | Should -Be ([System.Net.HttpStatusCode]::BadRequest)
    }

    It 'maps an ItemNotFoundException to 404' {
        Get-CaughtStatus { throw [System.Management.Automation.ItemNotFoundException]::new('Template not found') } | Should -Be ([System.Net.HttpStatusCode]::NotFound)
    }

    It 'maps a plain string throw, as Graph helpers raise, to 500' {
        Get-CaughtStatus { throw 'Graph returned 503' } | Should -Be ([System.Net.HttpStatusCode]::InternalServerError)
    }

    It 'finds the typed exception when PowerShell wraps it' {
        # A script block run through a .NET method surfaces as MethodInvocationException -> RuntimeException -> ArgumentException
        Get-CaughtStatus { { throw [System.ArgumentException]::new('bad') }.Invoke() } | Should -Be ([System.Net.HttpStatusCode]::BadRequest)
    }
}
