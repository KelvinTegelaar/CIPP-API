BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
    . (Join-Path $RepoRoot 'Modules/CIPPCore/Public/Get-CIPPLAPSPassword.ps1')

    function New-GraphGetRequest { param($NoAuthCheck, $uri, $tenantid) }
    function Write-LogMessage { param($headers, $API, $message, $Sev, $tenant, $LogData) }
    function Get-CippException { param($Exception) [pscustomobject]@{ NormalizedError = [string]$Exception.Exception.Message } }
}

Describe 'Get-CIPPLapsPassword' {
    It 'returns the credential when one exists' {
        Mock New-GraphGetRequest { [pscustomobject]@{ credentials = @([pscustomobject]@{ accountName = 'Administrator'; passwordBase64 = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes('secret')); BackupDateTime = '2026-09-01' }) } }
        $Result = Get-CIPPLapsPassword -Device 'dev-1' -TenantFilter 'contoso.com'
        $Result.state | Should -Be 'success'
        $Result.copyField | Should -Be 'secret'
    }

    It 'throws ItemNotFoundException when the device has no LAPS password' {
        Mock New-GraphGetRequest { [pscustomobject]@{ credentials = @() } }
        { Get-CIPPLapsPassword -Device 'dev-1' -TenantFilter 'contoso.com' } | Should -Throw 'No LAPS password found for dev-1' -ExceptionType ([System.Management.Automation.ItemNotFoundException])
    }

    It 'throws an untyped error when Graph fails' {
        Mock New-GraphGetRequest { throw 'Forbidden' }
        $Err = { Get-CIPPLapsPassword -Device 'dev-1' -TenantFilter 'contoso.com' } | Should -Throw 'Could not retrieve LAPS password for dev-1. Error: Forbidden' -PassThru
        $Err.Exception | Should -Not -BeOfType ([System.Management.Automation.ItemNotFoundException])
        $Err.Exception | Should -Not -BeOfType ([System.ArgumentException])
    }
}
