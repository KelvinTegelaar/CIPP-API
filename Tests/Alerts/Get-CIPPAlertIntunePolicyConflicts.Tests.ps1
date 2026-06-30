# Pester tests for Get-CIPPAlertIntunePolicyConflicts
# The alert reads pre-collected data from the CIPP reporting cache (Get-CIPPDbItem):
#   - Intune<PolicyType>_<policyId>  -> per-device compliance/config states (error/conflict)
#   - IntuneAppInstallStatusAggregate -> per-app install failure counts
# These tests mock the cache reads and verify aggregation, toggles, and error handling.

BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
    $AlertPath = Join-Path $RepoRoot 'Modules/CIPPAlerts/Public/Alerts/Get-CIPPAlertIntunePolicyConflicts.ps1'

    function Get-CIPPDbItem { param($TenantFilter, $Type, [switch]$CountsOnly) }
    function Write-AlertTrace { param($cmdletName, $tenantFilter, $data) }
    function Write-LogMessage { param($API, $tenant, $message, $sev, $LogData) }
    function Get-CippException { param($Exception) [pscustomobject]@{ NormalizedError = "$Exception" } }
    function Test-CIPPStandardLicense { param($StandardName, $TenantFilter, $Preset) }

    # Build a cache row the way Add-CIPPDbItem stores it: RowKey "<Type>-<id>", Data = compressed JSON.
    function New-DbItem {
        param($Type, $Id, $Object)
        [pscustomobject]@{
            RowKey = "$Type-$Id"
            Data   = ($Object | ConvertTo-Json -Compress -Depth 10)
        }
    }

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

        Mock -CommandName Write-LogMessage -MockWith {
            param($API, $tenant, $message, $sev, $LogData)
            $script:CapturedErrorMessage = $message
        }

        # Default cache: one compliance policy in conflict, one config profile in error, one failing app.
        Mock -CommandName Get-CIPPDbItem -MockWith {
            param($TenantFilter, $Type, [switch]$CountsOnly)
            switch ($Type) {
                'IntuneDeviceCompliancePolicies' { New-DbItem $Type 'comp-1' @{ id = 'comp-1'; displayName = 'Compliance A' } }
                'IntuneDeviceCompliancePolicies_comp-1' { New-DbItem $Type 'd1' @{ id = 'd1'; status = 'conflict'; deviceDisplayName = 'PC-01'; userPrincipalName = 'user1@contoso.com' } }
                'IntuneDeviceConfigurations' { New-DbItem $Type 'cfg-1' @{ id = 'cfg-1'; displayName = 'Config A' } }
                'IntuneDeviceConfigurations_cfg-1' { New-DbItem $Type 'd2' @{ id = 'd2'; status = 'error'; deviceDisplayName = 'PC-02'; userPrincipalName = 'user2@contoso.com' } }
                'IntuneAppInstallStatusAggregate' { New-DbItem $Type 'app-1' @{ displayName = 'App A'; failedDeviceCount = 3; failedUserCount = 2; failedDevicePercentage = 12; platform = 'Windows' } }
                default { @() }
            }
        }
    }

    It 'defaults to aggregated alerting across compliance, config and app sources' {
        Get-CIPPAlertIntunePolicyConflicts -TenantFilter 'contoso.onmicrosoft.com'

        $CapturedTenant | Should -Be 'contoso.onmicrosoft.com'
        $CapturedData | Should -Not -BeNullOrEmpty
        $CapturedData.Count | Should -Be 1
        $CapturedData[0].PolicyIssues | Should -Be 2   # compliance conflict + config error
        $CapturedData[0].AppIssues | Should -Be 1
        $CapturedData[0].Issues.Count | Should -Be 3
    }

    It 'emits per-issue alerts when AlertEachIssue is true' {
        Get-CIPPAlertIntunePolicyConflicts -TenantFilter 'contoso.onmicrosoft.com' -InputValue @{ AlertEachIssue = $true }

        $CapturedData | Should -Not -BeNullOrEmpty
        $CapturedData.Count | Should -Be 3
        ($CapturedData | Where-Object { $_.Type -eq 'Policy' }).Count | Should -Be 2
        ($CapturedData | Where-Object { $_.Type -eq 'Application' }).Count | Should -Be 1
    }

    It 'supports legacy Aggregate=false for per-issue alerts' {
        Get-CIPPAlertIntunePolicyConflicts -TenantFilter 'contoso.onmicrosoft.com' -InputValue @{ Aggregate = $false }

        $CapturedData | Should -Not -BeNullOrEmpty
        $CapturedData.Count | Should -Be 3
    }

    It 'honors IncludePolicies toggle' {
        Get-CIPPAlertIntunePolicyConflicts -TenantFilter 'contoso.onmicrosoft.com' -InputValue @{ IncludePolicies = $false }

        $CapturedData | Should -Not -BeNullOrEmpty
        $CapturedData.Count | Should -Be 1
        $CapturedData[0].PolicyIssues | Should -Be 0
        $CapturedData[0].AppIssues | Should -Be 1
        $CapturedData[0].Issues.Count | Should -Be 1
    }

    It 'honors IncludeApplications toggle' {
        Get-CIPPAlertIntunePolicyConflicts -TenantFilter 'contoso.onmicrosoft.com' -InputValue @{ IncludeApplications = $false }

        $CapturedData | Should -Not -BeNullOrEmpty
        $CapturedData[0].PolicyIssues | Should -Be 2
        $CapturedData[0].AppIssues | Should -Be 0
        ($CapturedData[0].Issues | Where-Object { $_.Type -eq 'Application' }).Count | Should -Be 0
    }

    It 'suppresses conflict states (and apps) when only AlertConflicts is requested' {
        # Only conflicts requested: config 'error' state and app failures are both suppressed,
        # leaving just the compliance conflict.
        Get-CIPPAlertIntunePolicyConflicts -TenantFilter 'contoso.onmicrosoft.com' -InputValue @{ AlertErrors = $false; Aggregate = $false }

        $CapturedData | Should -Not -BeNullOrEmpty
        $CapturedData.Count | Should -Be 1
        $CapturedData[0].Type | Should -Be 'Policy'
        $CapturedData[0].IssueStatus | Should -Be 'conflict'
        $CapturedData[0].PolicyType | Should -Be 'Compliance'
    }

    It 'reports aggregate app failure detail' {
        Get-CIPPAlertIntunePolicyConflicts -TenantFilter 'contoso.onmicrosoft.com' -InputValue @{ AlertEachIssue = $true; IncludePolicies = $false }

        $AppIssue = $CapturedData | Where-Object { $_.Type -eq 'Application' }
        $AppIssue.FailedDeviceCount | Should -Be 3
        $AppIssue.Message | Should -Match 'failed to install on 3 device'
    }

    It 'skips processing when license check fails' {
        Mock -CommandName Test-CIPPStandardLicense -MockWith { $false } -Verifiable

        Get-CIPPAlertIntunePolicyConflicts -TenantFilter 'contoso.onmicrosoft.com'

        $CapturedData | Should -BeNullOrEmpty
        $CapturedTenant | Should -BeNullOrEmpty
    }

    It 'writes alert message when a cache read fails' {
        Mock -CommandName Get-CIPPDbItem -MockWith { throw 'DB failure' } -Verifiable

        Get-CIPPAlertIntunePolicyConflicts -TenantFilter 'contoso.onmicrosoft.com'

        $CapturedData | Should -BeNullOrEmpty
        $CapturedErrorMessage | Should -Match 'Failed to read cached'
        $CapturedErrorMessage | Should -Match 'DB failure'
    }
}
