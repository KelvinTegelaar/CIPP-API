BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
    . (Join-Path $RepoRoot 'Modules/CIPPCore/Public/Get-CIPPMacOSLapsPassword.ps1')

    function New-GraphGetRequest { param($uri, $tenantid) }
    function Write-LogMessage { param($headers, $API, $message, $Sev, $tenant, $LogData) }
    function Get-CippException { param($Exception) [pscustomobject]@{ NormalizedError = [string]$Exception.Exception.Message } }

    $script:DeviceId = '11111111-2222-3333-4444-555555555555'
}

Describe 'Get-CIPPMacOSLapsPassword' {
    It 'returns the credential when one exists' {
        Mock New-GraphGetRequest { [pscustomobject]@{ adminAccountPassword = 'secret'; passwordLastRotatedDateTime = '2026-09-01T00:00:00Z' } }
        $Result = Get-CIPPMacOSLapsPassword -Device $script:DeviceId -TenantFilter 'contoso.com'
        $Result.state | Should -Be 'success'
        $Result.copyField | Should -Be 'secret'
        $Result.passwordLastRotatedDateTime | Should -Be '2026-09-01T00:00:00Z'
    }

    It 'calls the managed device function for the one device named' {
        Mock New-GraphGetRequest { [pscustomobject]@{ adminAccountPassword = 'secret' } }
        Get-CIPPMacOSLapsPassword -Device $script:DeviceId -TenantFilter 'contoso.com'
        Should -Invoke New-GraphGetRequest -Times 1 -ParameterFilter {
            $uri -eq "https://graph.microsoft.com/beta/deviceManagement/managedDevices/$($script:DeviceId)/retrieveMacOSManagedDeviceLocalAdminAccountDetail" -and $tenantid -eq 'contoso.com'
        }
    }

    It 'throws ArgumentException without calling Graph when the device ID is not a GUID' {
        Mock New-GraphGetRequest { }
        { Get-CIPPMacOSLapsPassword -Device '../../users' -TenantFilter 'contoso.com' } | Should -Throw -ExceptionType ([System.ArgumentException])
        Should -Invoke New-GraphGetRequest -Times 0
    }

    It 'throws ItemNotFoundException when the device has no LAPS password' {
        Mock New-GraphGetRequest { [pscustomobject]@{ adminAccountPassword = $null; passwordLastRotatedDateTime = $null } }
        { Get-CIPPMacOSLapsPassword -Device $script:DeviceId -TenantFilter 'contoso.com' } | Should -Throw "No macOS LAPS password found for $($script:DeviceId)" -ExceptionType ([System.Management.Automation.ItemNotFoundException])
    }

    It 'throws an untyped error when Graph fails' {
        Mock New-GraphGetRequest { throw 'Forbidden' }
        $Err = { Get-CIPPMacOSLapsPassword -Device $script:DeviceId -TenantFilter 'contoso.com' } | Should -Throw "Could not retrieve macOS LAPS password for $($script:DeviceId). Error: Forbidden" -PassThru
        $Err.Exception | Should -Not -BeOfType ([System.Management.Automation.ItemNotFoundException])
        $Err.Exception | Should -Not -BeOfType ([System.ArgumentException])
    }
}
