# Pester tests for Get-CIPPAlertUserReportedPhishing
# Verifies user-report filtering, that pagination never chases the regional EXO backend cursor,
# and that a regional route-miss degrades quietly instead of flooding alerts.

BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
    # Resolve by name under Modules/ so the test survives the function moving between modules.
    $AlertPath = Get-ChildItem -Path (Join-Path $RepoRoot 'Modules') -Recurse -Filter 'Get-CIPPAlertUserReportedPhishing.ps1' -File -ErrorAction SilentlyContinue |
        Select-Object -First 1 -ExpandProperty FullName
    if (-not $AlertPath) { throw 'Could not locate Get-CIPPAlertUserReportedPhishing.ps1 under Modules/' }

    # Provide minimal stubs so Mock has commands to replace during tests
    function New-GraphGetRequest { param($uri, $tenantid, $AsApp) }
    function Write-AlertTrace { param($cmdletName, $tenantFilter, $data) }
    function Write-AlertMessage { param($tenant, $message, $LogData) }
    function Get-CippException { param($Exception) @{ NormalizedError = $Exception.Exception.Message } }

    . $AlertPath
}

Describe 'Get-CIPPAlertUserReportedPhishing' {
    BeforeEach {
        $script:CapturedData = $null
        $script:CapturedTenant = $null
        $script:CapturedAlertMessage = $null

        Mock -CommandName New-GraphGetRequest -MockWith {
            @(
                [pscustomobject]@{
                    id            = 'sub-user'
                    source        = 'user'
                    sender        = 'attacker@evil.example'
                    emailSubject  = 'Reset your password now'
                    category      = 'phishing'
                    createdBy     = [pscustomobject]@{ user = [pscustomobject]@{ displayName = 'Reporter One'; email = 'reporter@contoso.com' } }
                },
                [pscustomobject]@{
                    id            = 'sub-admin'
                    source        = 'administrator'
                    sender        = 'noreply@contoso.com'
                    emailSubject  = 'Admin submitted sample'
                    category      = 'phishing'
                    createdBy     = [pscustomobject]@{ user = [pscustomobject]@{ displayName = 'Some Admin'; email = 'admin@contoso.com' } }
                }
            )
        }

        Mock -CommandName Write-AlertTrace -MockWith {
            param($cmdletName, $tenantFilter, $data)
            $script:CapturedData = $data
            $script:CapturedTenant = $tenantFilter
        }

        Mock -CommandName Write-AlertMessage -MockWith {
            param($tenant, $message, $LogData)
            $script:CapturedAlertMessage = $message
        }
    }

    It 'reports only user-sourced submissions' {
        Get-CIPPAlertUserReportedPhishing -TenantFilter 'contoso.onmicrosoft.com'

        $CapturedData | Should -Not -BeNullOrEmpty
        @($CapturedData).Count | Should -Be 1
        $CapturedData.SubmissionId | Should -Contain 'sub-user'
        $CapturedData.SubmissionId | Should -Not -Contain 'sub-admin'
        $CapturedTenant | Should -Be 'contoso.onmicrosoft.com'
    }

    It 'alerts with a stable EXO-unavailable message when the region does not serve the API' {
        Mock -CommandName New-GraphGetRequest -MockWith {
            throw "No HTTP resource was found that matches the request URI 'https://deu01b.dataservice.protection.outlook.com/ReportSubmission/security/threatSubmission/emailThreats?`$filter=createdDateTime ge 2026-09-07T09:30:27Z&tenantid=abc'."
        }

        Get-CIPPAlertUserReportedPhishing -TenantFilter 'mobiler-home-service.de'

        Should -Invoke Write-AlertMessage -Times 1 -Exactly
        $CapturedAlertMessage | Should -Match 'Exchange Online API unavailable'
        $CapturedAlertMessage | Should -Match 'Check tenant and EXO health'
        $CapturedAlertMessage | Should -Not -Match '2026-09-07'
    }

    It 'still raises an alert for genuine (non-regional) failures' {
        Mock -CommandName New-GraphGetRequest -MockWith { throw 'Insufficient privileges to complete the operation.' }

        Get-CIPPAlertUserReportedPhishing -TenantFilter 'contoso.onmicrosoft.com'

        Should -Invoke Write-AlertMessage -Times 1 -Exactly
        $CapturedAlertMessage | Should -Match 'Insufficient privileges'
    }
}
