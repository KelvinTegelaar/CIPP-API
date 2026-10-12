BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
    . (Join-Path $RepoRoot 'Modules/CIPPCore/Public/New-CippCustomScriptExecution.ps1')
    . (Join-Path $RepoRoot 'Modules/CIPPCore/Public/Get-CippErrorStatusCode.ps1')

    function Get-CippTable { param($tablename) @{ Context = 'ctx' } }
    function Get-CIPPAzDataTableEntity { param($Context, $Filter) }
    function Get-CIPPTextReplacement { param($TenantFilter, $Text) $Text }
    function Test-CustomScriptSecurity { param($ScriptContent) }
    function Get-CippSandboxData { param($ScriptContent, $TenantFilter) }
    function Invoke-CippSandboxScript { param($ScriptContent, $SandboxData, $ScriptParameters) }
    function Write-LogMessage { param($API, $tenant, $message, $sev) }

    function Get-CaughtStatus([scriptblock]$Thrower) {
        try { & $Thrower } catch { [int](Get-CippErrorStatusCode -ErrorRecord $_) }
    }
}

Describe 'New-CippCustomScriptExecution error contract' {
    BeforeEach {
        Mock Get-CIPPAzDataTableEntity { [pscustomobject]@{ ScriptGuid = 'g'; Version = 1; ScriptContent = 'Get-Thing' } }
    }

    It 'throws ItemNotFoundException (404) when the script does not exist' {
        Mock Get-CIPPAzDataTableEntity { $null }
        { New-CippCustomScriptExecution -ScriptGuid 'missing' -TenantFilter 't' } |
            Should -Throw -ExceptionType ([System.Management.Automation.ItemNotFoundException]) -ExpectedMessage "Script with GUID 'missing' not found"
        Get-CaughtStatus { New-CippCustomScriptExecution -ScriptGuid 'missing' -TenantFilter 't' } | Should -Be 404
    }

    It 'throws ArgumentException (400) with the same message when the script fails the security check' {
        Mock Test-CustomScriptSecurity { throw "Security violation at line 1: Command 'Remove-Item' is not in the allowed list." }
        { New-CippCustomScriptExecution -ScriptGuid 'g' -TenantFilter 't' } |
            Should -Throw -ExceptionType ([System.ArgumentException]) -ExpectedMessage "Security violation at line 1: Command 'Remove-Item' is not in the allowed list."
    }

    It 'keeps an execution failure as a plain error (500)' {
        Mock Invoke-CippSandboxScript { [pscustomobject]@{ Output = $null; Errors = @('boom'); Terminating = $true; HadErrors = $true } }
        Get-CaughtStatus { New-CippCustomScriptExecution -ScriptGuid 'g' -TenantFilter 't' } | Should -Be 500
    }

    It 'returns the script output on success' {
        Mock Invoke-CippSandboxScript { [pscustomobject]@{ Output = @('row'); Errors = @(); Terminating = $false; HadErrors = $false } }
        New-CippCustomScriptExecution -ScriptGuid 'g' -TenantFilter 't' | Should -Be 'row'
    }
}
