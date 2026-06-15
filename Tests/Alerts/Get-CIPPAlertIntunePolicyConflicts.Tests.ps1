# Pester tests for Get-CIPPAlertIntunePolicyConflicts
# Verifies aggregation defaults, toggles, and error handling

BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
    # Resolve by name under Modules/ so the test survives the function moving between modules.
    $AlertPath = Get-ChildItem -Path (Join-Path $RepoRoot 'Modules') -Recurse -Filter 'Get-CIPPAlertIntunePolicyConflicts.ps1' -File -ErrorAction SilentlyContinue |
        Select-Object -First 1 -ExpandProperty FullName
    if (-not $AlertPath) { throw 'Could not locate Get-CIPPAlertIntunePolicyConflicts.ps1 under Modules/' }

    function New-GraphGetRequest { param($uri, $tenantid) }
    function Write-AlertTrace { param($cmdletName, $tenantFilter, $data) }
    function Write-AlertMessage { param($tenant, $message) }
    function Get-NormalizedError { param($message) $message }
    function Test-CIPPStandardLicense { param($StandardName, $TenantFilter, $RequiredCapabilities) }
    # The error path now normalises via Get-CippException and logs via Write-LogMessage.
    function Get-CippException { param($Exception) @{ NormalizedError = $Exception } }
    function Write-LogMessage { param($API, $tenant, $message, $sev, $Headers, $LogData) }

    . $AlertPath
}

Describe 'Get-CIPPAlertIntunePolicyConflicts' {
    BeforeEach {
        $script:CapturedData = $null
        $script:CapturedTenant = $null
        $script:CapturedErrorMessage = $null

        Mock -CommandName Test-CIPPStandardLicense -MockWith { $true }

        Mock -CommandName Write-AlertTrace -MockWith {
            param($cmdletName, $tenantFilter, $data)
            $script:CapturedData = $data
            $script:CapturedTenant = $tenantFilter
        }

        Mock -CommandName Write-AlertMessage -MockWith {
            param($tenant, $message)
            $script:CapturedErrorMessage = $message
        }

        # The function logs failures through Write-LogMessage, so capture the error from there.
        Mock -CommandName Write-LogMessage -MockWith {
            param($API, $tenant, $message, $sev, $Headers, $LogData)
            $script:CapturedErrorMessage = $message
        }

        Mock -CommandName New-GraphGetRequest -MockWith {
            param($uri, $tenantid)
            if ($uri -like '*deviceManagement/managedDevices*') {
                @(
                    [pscustomobject]@{
                        deviceName               = 'PC-01'
                        userPrincipalName        = 'user1@contoso.com'
                        id                       = 'device-1'
                        deviceConfigurationStates = @(
                            [pscustomobject]@{ displayName = 'Policy A'; state = 'conflict' }
                        )
                    }
                )
            } elseif ($uri -like '*deviceAppManagement/mobileApps*') {
                @(
                    [pscustomobject]@{
                        displayName   = 'App A'
                        deviceStatuses = @(
                            [pscustomobject]@{ installState = 'error'; deviceName = 'PC-01'; userPrincipalName = 'user1@contoso.com'; deviceId = 'device-1' }
                        )
                    }
                )
            }
        }
    }

    It 'defaults to aggregated alerting with all mechanisms and statuses' {
        Get-CIPPAlertIntunePolicyConflicts -TenantFilter 'contoso.onmicrosoft.com'

        $CapturedTenant | Should -Be 'contoso.onmicrosoft.com'
        $CapturedData | Should -Not -BeNullOrEmpty
        $CapturedData.Count | Should -Be 1
        $CapturedData[0].PolicyIssues | Should -Be 1
        $CapturedData[0].AppIssues | Should -Be 1
        $CapturedData[0].Issues.Count | Should -Be 2
    }

    It 'emits per-issue alerts when AlertEachIssue is true' {
        Get-CIPPAlertIntunePolicyConflicts -TenantFilter 'contoso.onmicrosoft.com' -InputValue @{ AlertEachIssue = $true }

        $CapturedData | Should -Not -BeNullOrEmpty
        $CapturedData.Count | Should -Be 2
        ($CapturedData | Where-Object { $_.Type -eq 'Policy' }).Count | Should -Be 1
        ($CapturedData | Where-Object { $_.Type -eq 'Application' }).Count | Should -Be 1
    }

    It 'supports legacy Aggregate=false for per-issue alerts' {
        Get-CIPPAlertIntunePolicyConflicts -TenantFilter 'contoso.onmicrosoft.com' -InputValue @{ Aggregate = $false }

        $CapturedData | Should -Not -BeNullOrEmpty
        $CapturedData.Count | Should -Be 2
        ($CapturedData | Where-Object { $_.Type -eq 'Policy' }).Count | Should -Be 1
        ($CapturedData | Where-Object { $_.Type -eq 'Application' }).Count | Should -Be 1
    }

    It 'honors IncludePolicies toggle' {
        Get-CIPPAlertIntunePolicyConflicts -TenantFilter 'contoso.onmicrosoft.com' -InputValue @{ IncludePolicies = $false }

        $CapturedData | Should -Not -BeNullOrEmpty
        $CapturedData.Count | Should -Be 1
        $CapturedData[0].PolicyIssues | Should -Be 0
        $CapturedData[0].AppIssues | Should -Be 1
        $CapturedData[0].Issues.Count | Should -Be 1
        ($CapturedData[0].Issues | Where-Object { $_.Type -eq 'Policy' }).Count | Should -Be 0
    }

    It 'suppresses conflict-only alerts when AlertConflicts is false' {
        # conflict for policy, error for app; expect only app when conflicts suppressed
        Mock -CommandName New-GraphGetRequest -MockWith {
            param($uri, $tenantid)
            if ($uri -like '*deviceManagement/managedDevices*') {
                @(
                    [pscustomobject]@{
                        deviceName               = 'PC-02'
                        userPrincipalName        = 'user2@contoso.com'
                        id                       = 'device-2'
                        deviceConfigurationStates = @(
                            [pscustomobject]@{ displayName = 'Policy B'; state = 'conflict' }
                        )
                    }
                )
            } elseif ($uri -like '*deviceAppManagement/mobileApps*') {
                @(
                    [pscustomobject]@{
                        displayName   = 'App B'
                        deviceStatuses = @(
                            [pscustomobject]@{ installState = 'error'; deviceName = 'PC-02'; userPrincipalName = 'user2@contoso.com'; deviceId = 'device-2' }
                        )
                    }
                )
            }
        }

        Get-CIPPAlertIntunePolicyConflicts -TenantFilter 'contoso.onmicrosoft.com' -InputValue @{ AlertConflicts = $false; Aggregate = $false }

        $CapturedData | Should -Not -BeNullOrEmpty
        $CapturedData.Count | Should -Be 1
        $CapturedData[0].Type | Should -Be 'Application'
        $CapturedData[0].IssueStatus | Should -Be 'error'
    }

    It 'skips processing when license check fails' {
        Mock -CommandName Test-CIPPStandardLicense -MockWith { $false } -Verifiable

        Get-CIPPAlertIntunePolicyConflicts -TenantFilter 'contoso.onmicrosoft.com'

        $CapturedData | Should -BeNullOrEmpty
        $CapturedTenant | Should -BeNullOrEmpty
    }

    It 'writes alert message when Graph call fails' {
        Mock -CommandName New-GraphGetRequest -MockWith { throw 'Graph failure' } -Verifiable

        Get-CIPPAlertIntunePolicyConflicts -TenantFilter 'contoso.onmicrosoft.com'

        $CapturedData | Should -BeNullOrEmpty
        $CapturedErrorMessage | Should -Match 'Failed to query Intune (policy|application) states'
        $CapturedErrorMessage | Should -Match 'Graph failure'
    }
}
