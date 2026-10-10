# Pester tests for MFA users alert new-account grace period.

BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
    $AlertPath = Join-Path $RepoRoot 'Modules/CIPPAlerts/Public/Alerts/Get-CIPPAlertMFAAlertUsers.ps1'

    function Get-CIPPMFAStateReport { param($TenantFilter) }
    function New-CIPPDbRequest { param($TenantFilter, $Type, $Fields) }
    function New-GraphGETRequest { param($uri, $tenantid, $AsApp) }
    function Write-AlertTrace { param($cmdletName, $tenantFilter, $data) }
    function Write-LogMessage { param($message, $API, $tenant, $sev) }

    . $AlertPath
}

Describe 'Get-CIPPAlertMFAAlertUsers grace period' {
    BeforeEach {
        $script:CapturedData = $null
        $script:GraphCalled = $false

        Mock -CommandName Write-AlertTrace -MockWith {
            param($cmdletName, $tenantFilter, $data)
            $script:CapturedData = @($data)
        }
        Mock -CommandName Write-LogMessage -MockWith { }
        Mock -CommandName Get-CIPPMFAStateReport -MockWith {
            @(
                [pscustomobject]@{ UPN = 'new@contoso.com'; DisplayName = 'New'; IsAdmin = $false; MFARegistration = $false; UserType = 'Member' }
                [pscustomobject]@{ UPN = 'old@contoso.com'; DisplayName = 'Old'; IsAdmin = $false; MFARegistration = $false; UserType = 'Member' }
                [pscustomobject]@{ UPN = 'missing@contoso.com'; DisplayName = 'Missing'; IsAdmin = $false; MFARegistration = $false; UserType = 'Member' }
            )
        }
    }

    It 'excludes only known-young accounts from cache; keeps missing and old' {
        Mock -CommandName New-CIPPDbRequest -MockWith {
            @(
                [pscustomobject]@{ userPrincipalName = 'new@contoso.com'; createdDateTime = (Get-Date).ToUniversalTime().AddDays(-2) }
                [pscustomobject]@{ userPrincipalName = 'old@contoso.com'; createdDateTime = (Get-Date).ToUniversalTime().AddDays(-30) }
            )
        }
        Mock -CommandName New-GraphGETRequest -MockWith { throw 'Graph must not be called when cache has data' }

        Get-CIPPAlertMFAAlertUsers -TenantFilter 'contoso.onmicrosoft.com' -InputValue 7

        $Upns = @($script:CapturedData | ForEach-Object { $_.UserPrincipalName })
        $Upns | Should -Contain 'old@contoso.com'
        $Upns | Should -Contain 'missing@contoso.com'
        $Upns | Should -Not -Contain 'new@contoso.com'
    }

    It 'falls back to live Graph when cache is empty and applies the same rule' {
        Mock -CommandName New-CIPPDbRequest -MockWith { @() }
        Mock -CommandName New-GraphGETRequest -MockWith {
            $script:GraphCalled = $true
            @(
                [pscustomobject]@{ userPrincipalName = 'new@contoso.com'; createdDateTime = (Get-Date).ToUniversalTime().AddDays(-1) }
                [pscustomobject]@{ userPrincipalName = 'old@contoso.com'; createdDateTime = (Get-Date).ToUniversalTime().AddDays(-40) }
            )
        }

        Get-CIPPAlertMFAAlertUsers -TenantFilter 'contoso.onmicrosoft.com' -InputValue 7

        $script:GraphCalled | Should -BeTrue
        $Upns = @($script:CapturedData | ForEach-Object { $_.UserPrincipalName })
        $Upns | Should -Contain 'old@contoso.com'
        $Upns | Should -Contain 'missing@contoso.com'
        $Upns | Should -Not -Contain 'new@contoso.com'
    }

    It 'does not apply grace filtering when days is 0' {
        Mock -CommandName New-CIPPDbRequest -MockWith { throw 'DB must not be queried when grace is disabled' }
        Mock -CommandName New-GraphGETRequest -MockWith { throw 'Graph must not be queried when grace is disabled' }

        Get-CIPPAlertMFAAlertUsers -TenantFilter 'contoso.onmicrosoft.com' -InputValue 0

        $Upns = @($script:CapturedData | ForEach-Object { $_.UserPrincipalName })
        $Upns.Count | Should -Be 3
    }
}
