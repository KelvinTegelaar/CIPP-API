# Pester tests for the primary-user branches of New-CIPPDeviceAction.
# Removing the primary user is a DELETE on the managed device's users/$ref (what the Intune portal sends).

BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
    $FunctionPath = Join-Path $RepoRoot 'Modules/CIPPCore/Public/New-CIPPDeviceAction.ps1'

    function New-GraphPOSTRequest { param($uri, $type, $tenantid, $body) }
    function Write-LogMessage { param($headers, $API, $tenant, $message, $Sev, $LogData) }
    function Get-CippException { param($Exception) }
    function Invoke-CIPPMDEOffboard { param($AzureADDeviceId, $TenantFilter) }

    . $FunctionPath
}

Describe 'New-CIPPDeviceAction - removePrimaryUser' {
    BeforeEach {
        Mock -CommandName Write-LogMessage -MockWith { }
        Mock -CommandName New-GraphPOSTRequest -MockWith { }
    }

    It 'sends a DELETE to users/$ref on the managed device' {
        $Result = New-CIPPDeviceAction -Action 'removePrimaryUser' -ActionBody '{"Action":"removePrimaryUser"}' -DeviceFilter 'device-guid' -TenantFilter 'contoso.com'

        $Result | Should -Be 'Removed primary user from device device-guid'
        Should -Invoke New-GraphPOSTRequest -Times 1 -Exactly -ParameterFilter {
            $uri -eq "https://graph.microsoft.com/beta/deviceManagement/managedDevices('device-guid')/users/`$ref" -and
            $type -eq 'DELETE' -and
            $tenantid -eq 'contoso.com'
        }
    }

    It 'throws a failure message when Graph rejects the call' {
        Mock -CommandName New-GraphPOSTRequest -MockWith { throw 'boom' }
        Mock -CommandName Get-CippException -MockWith { [pscustomobject]@{ NormalizedError = 'No primary user' } }

        { New-CIPPDeviceAction -Action 'removePrimaryUser' -DeviceFilter 'device-guid' -TenantFilter 'contoso.com' } |
            Should -Throw '*removePrimaryUser*No primary user*'
    }
}
