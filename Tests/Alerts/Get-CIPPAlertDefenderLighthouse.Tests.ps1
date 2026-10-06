# Get-CIPPAlertDefenderMalware and Get-CIPPAlertDefenderStatus read Lighthouse managedTenants data from the
# partner tenant. When Lighthouse is unavailable Graph answers every tenant with "Request not applicable to
# target tenant.", which must not be logged as an error; every other failure still is.

BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
    $Alerts = Join-Path $RepoRoot 'Modules/CIPPAlerts/Public/Alerts'

    function Get-Tenants { param($TenantFilter) }
    function New-GraphGetRequest { param($uri, $tenantid) }
    function Write-AlertTrace { param($cmdletName, $tenantFilter, $data) }
    function Write-LogMessage { param($API, $tenant, $message, $sev, $LogData) }
    function Get-NormalizedError { param($message) $message }

    . (Join-Path $RepoRoot 'Modules/CIPPCore/Public/GraphHelper/Get-CippException.ps1')
    . (Join-Path $Alerts 'Get-CIPPAlertDefenderMalware.ps1')
    . (Join-Path $Alerts 'Get-CIPPAlertDefenderStatus.ps1')
}

Describe '<Alert> when Graph fails' -ForEach @(
    @{ Alert = 'Get-CIPPAlertDefenderMalware' }
    @{ Alert = 'Get-CIPPAlertDefenderStatus' }
) {
    BeforeEach {
        Mock Get-Tenants { [pscustomobject]@{ customerId = 'cust-1' } }
        Mock Write-AlertTrace {}
        Mock Write-LogMessage {}
    }

    It 'does not log when Lighthouse is unavailable' {
        Mock New-GraphGetRequest { throw 'Request not applicable to target tenant.' }
        & $Alert -TenantFilter 'contoso.onmicrosoft.com'
        Should -Not -Invoke Write-LogMessage
        Should -Not -Invoke Write-AlertTrace
    }

    It 'still logs any other error' {
        Mock New-GraphGetRequest { throw 'Forbidden' }
        & $Alert -TenantFilter 'contoso.onmicrosoft.com'
        Should -Invoke Write-LogMessage -Times 1 -Exactly -ParameterFilter { $sev -eq 'Error' -and $message -like '*Forbidden*' }
    }
}
