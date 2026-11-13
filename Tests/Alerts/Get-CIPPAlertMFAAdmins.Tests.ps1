# MFA admins alert: only an enabled Duo conditional access policy skips the check; a disabled or report-only
# one enforces nothing, so the alert still runs.

BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))

    function New-GraphGetRequest { param($uri, $tenantid, $AsApp, [switch]$ComplexFilter) }
    function Get-CIPPMFAStateReport { param($TenantFilter) }
    function Get-CIPPSchemaExtensions { }
    function Write-LogMessage { param($message, $API, $tenant, $sev, $LogData) }
    function Write-AlertTrace { param($cmdletName, $tenantFilter, $data) }

    . (Join-Path $RepoRoot 'Modules/CIPPAlerts/Public/Alerts/Get-CIPPAlertMFAAdmins.ps1')
}

Describe 'Get-CIPPAlertMFAAdmins' {
    BeforeEach {
        Mock Write-LogMessage { }
        Mock Write-AlertTrace { }
        Mock Get-CIPPSchemaExtensions { [PSCustomObject]@{ id = 'extabc_cippUser' } }
        Mock Get-CIPPMFAStateReport {
            [PSCustomObject]@{ ID = 'u1'; UPN = 'admin@contoso.com'; DisplayName = 'Admin'; IsAdmin = $true; MFARegistration = $false; UserType = 'Member'; AccountEnabled = $true }
        }
        Mock New-GraphGetRequest { }
    }

    It 'still checks admins when the Duo policy is report-only' {
        Mock New-GraphGetRequest -ParameterFilter { $uri -like '*conditionalAccess/policies*' } {
            [PSCustomObject]@{ state = 'enabledForReportingButNotEnforced'; grantControls = [PSCustomObject]@{ customAuthenticationFactors = @('RequireDuoMfa') } }
        }
        Get-CIPPAlertMFAAdmins -TenantFilter 'contoso.onmicrosoft.com'
        Should -Invoke Write-AlertTrace -Times 1 -Exactly -ParameterFilter { $data.Count -eq 1 -and $data[0].UserPrincipalName -eq 'admin@contoso.com' }
    }

    It 'skips the check when the Duo policy is enabled' {
        Mock New-GraphGetRequest -ParameterFilter { $uri -like '*conditionalAccess/policies*' } {
            [PSCustomObject]@{ state = 'enabled'; grantControls = [PSCustomObject]@{ customAuthenticationFactors = @('RequireDuoMfa') } }
        }
        Get-CIPPAlertMFAAdmins -TenantFilter 'contoso.onmicrosoft.com'
        Should -Invoke Write-AlertTrace -Times 0 -Exactly
    }
}
