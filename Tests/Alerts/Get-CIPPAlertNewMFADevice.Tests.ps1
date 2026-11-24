# Pester tests for Get-CIPPAlertNewMFADevice UPN pattern filtering.

BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
    $AlertPath = Join-Path $RepoRoot 'Modules/CIPPAlerts/Public/Alerts/Get-CIPPAlertNewMFADevice.ps1'

    function New-GraphGetRequest { param($uri, $tenantid) }
    function Get-CIPPTextReplacement { param($TenantFilter, $Text) }
    function Get-CIPPGeoIPLocation { param($IP) }
    function Get-CippException { param($Exception) }
    function Write-AlertTrace { param($cmdletName, $tenantFilter, $data) }
    function Write-LogMessage { param($message, $API, $tenant, $sev, $LogData) }

    . $AlertPath

    function New-RegLog {
        param($Upn, $Ip = '203.0.113.5')
        [pscustomobject]@{
            activityDisplayName = 'User registered security info'
            activityDateTime    = '2026-01-01T00:00:00Z'
            targetResources     = @([pscustomobject]@{ userPrincipalName = $Upn; displayName = $Upn })
            initiatedBy         = [pscustomobject]@{ user = [pscustomobject]@{ userPrincipalName = $Upn; ipAddress = $Ip } }
        }
    }
}

Describe 'Get-CIPPAlertNewMFADevice' {
    BeforeEach {
        $script:Logs = @(
            (New-RegLog 'breakglass@contoso.com'),
            (New-RegLog 'alice@contoso.com'),
            (New-RegLog 'BreakGlass2@fabrikam.com')
        )
        $script:Captured = $null
        Mock New-GraphGetRequest { $script:Logs }
        Mock Get-CIPPTextReplacement { param($TenantFilter, $Text) $Text }
        Mock Get-CIPPGeoIPLocation { [pscustomobject]@{ countryCode = 'US' } }
        Mock Write-LogMessage {}
        Mock Write-AlertTrace {
            param($cmdletName, $tenantFilter, $data)
            $script:Captured = @($data | Where-Object { $null -ne $_ })
        }
    }

    It 'alerts for every registration when no input is set' {
        Get-CIPPAlertNewMFADevice -TenantFilter 'contoso.onmicrosoft.com'
        $script:Captured.Count | Should -Be 3
        Should -Invoke Get-CIPPGeoIPLocation -Times 3 -Exactly
    }

    It 'filters on a single wildcard pattern and skips the GeoIP lookup for others' {
        Get-CIPPAlertNewMFADevice -InputValue 'breakglass@*' -TenantFilter 'contoso.onmicrosoft.com'
        $script:Captured.Count | Should -Be 1
        $script:Captured[0].User | Should -Be 'breakglass@contoso.com'
        Should -Invoke Get-CIPPGeoIPLocation -Times 1 -Exactly
    }

    It 'handles a comma list with spaces' {
        Get-CIPPAlertNewMFADevice -InputValue ' alice@contoso.com ,  breakglass2@* ' -TenantFilter 'contoso.onmicrosoft.com'
        $script:Captured.User | Should -Be @('alice@contoso.com', 'BreakGlass2@fabrikam.com')
    }

    It 'matches case-insensitively' {
        Get-CIPPAlertNewMFADevice -InputValue 'BREAKGLASS@CONTOSO.COM' -TenantFilter 'contoso.onmicrosoft.com'
        $script:Captured.Count | Should -Be 1
        $script:Captured[0].User | Should -Be 'breakglass@contoso.com'
    }

    It 'treats whitespace-only input as empty' {
        Get-CIPPAlertNewMFADevice -InputValue '  , ' -TenantFilter 'contoso.onmicrosoft.com'
        $script:Captured.Count | Should -Be 3
    }

    It 'accepts an object carrying InputValue' {
        Get-CIPPAlertNewMFADevice -InputValue ([pscustomobject]@{ InputValue = 'alice@*' }) -TenantFilter 'contoso.onmicrosoft.com'
        $script:Captured.Count | Should -Be 1
        $script:Captured[0].User | Should -Be 'alice@contoso.com'
    }

    It 'expands %variables% for the tenant before matching' {
        Mock Get-CIPPTextReplacement { 'breakglass@contoso.com' }
        Get-CIPPAlertNewMFADevice -InputValue 'breakglass@%defaultdomain%' -TenantFilter 'contoso.onmicrosoft.com'
        Should -Invoke Get-CIPPTextReplacement -Times 1 -Exactly -ParameterFilter { $TenantFilter -eq 'contoso.onmicrosoft.com' -and $Text -eq 'breakglass@%defaultdomain%' }
        $script:Captured.Count | Should -Be 1
        $script:Captured[0].User | Should -Be 'breakglass@contoso.com'
    }

    It 'splits a variable whose value is itself a comma list' {
        Mock Get-CIPPTextReplacement { 'alice@contoso.com, breakglass2@*' }
        Get-CIPPAlertNewMFADevice -InputValue '%breakglassupns%' -TenantFilter 'contoso.onmicrosoft.com'
        $script:Captured.User | Should -Be @('alice@contoso.com', 'BreakGlass2@fabrikam.com')
    }

    It 'skips registrations with no resolvable UPN when patterns are set' {
        $NoUpn = New-RegLog $null
        $script:Logs = @($NoUpn, (New-RegLog 'alice@contoso.com'))
        Get-CIPPAlertNewMFADevice -InputValue 'alice@*' -TenantFilter 'contoso.onmicrosoft.com'
        $script:Captured.Count | Should -Be 1
    }

    It 'still ignores deleted security info events' {
        $Deleted = New-RegLog 'breakglass@contoso.com'
        $Deleted.activityDisplayName = 'User deleted security info'
        $script:Logs = @($Deleted)
        Get-CIPPAlertNewMFADevice -InputValue 'breakglass@*' -TenantFilter 'contoso.onmicrosoft.com'
        $script:Captured.Count | Should -Be 0
    }
}
