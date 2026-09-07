# Pester tests for Get-CIPPAlertOneDriveLongPaths (cache-backed, count-only alerts).

BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
    $AlertPath = Join-Path $RepoRoot 'Modules/CIPPAlerts/Public/Alerts/Get-CIPPAlertOneDriveLongPaths.ps1'

    function New-CIPPDbRequest { param($TenantFilter, $Type, $Fields) }
    function Write-AlertTrace { param($cmdletName, $tenantFilter, $data) }
    function Write-AlertMessage { param($message, $tenant, $tenantId, $LogData) }
    function Write-LogMessage { param($API, $tenant, $message, $sev, $LogData) }
    function Get-CippException { param($Exception) [pscustomobject]@{ NormalizedError = "$Exception" } }
    function Test-CIPPStandardLicense { param($StandardName, $TenantFilter, $Preset) }

    . $AlertPath
}

Describe 'Get-CIPPAlertOneDriveLongPaths' {
    BeforeEach {
        $script:CapturedData = $null
        Mock -CommandName Test-CIPPStandardLicense -MockWith { $true }
        Mock -CommandName Write-AlertTrace -MockWith {
            param($cmdletName, $tenantFilter, $data)
            $script:CapturedData = @($data)
        }
        Mock -CommandName Write-AlertMessage -MockWith { }
    }

    It 'no-ops when cache is empty' {
        Mock -CommandName New-CIPPDbRequest -MockWith { @() }
        Get-CIPPAlertOneDriveLongPaths -TenantFilter 'contoso.onmicrosoft.com'
        $script:CapturedData | Should -BeNullOrEmpty
    }

    It 'emits count-only alerts for users over the minimum' {
        Mock -CommandName New-CIPPDbRequest -MockWith {
            @(
                [pscustomobject]@{ ownerPrincipalName = 'a@contoso.com'; countOver260 = 5; countOver400 = 1 }
                [pscustomobject]@{ ownerPrincipalName = 'b@contoso.com'; countOver260 = 0; countOver400 = 0 }
            )
        }
        Get-CIPPAlertOneDriveLongPaths -TenantFilter 'contoso.onmicrosoft.com'

        $script:CapturedData | Should -Not -BeNullOrEmpty
        $script:CapturedData.Count | Should -Be 1
        $script:CapturedData[0].ownerPrincipalName | Should -Be 'a@contoso.com'
        $script:CapturedData[0].countOver260 | Should -Be 5
        $script:CapturedData[0].countOver400 | Should -Be 1
        $script:CapturedData[0].Message | Should -Match 'a@contoso.com'
        $script:CapturedData[0].Message | Should -Match '5'
        $script:CapturedData[0].PSObject.Properties.Name | Should -Not -Contain 'webUrl'
        $script:CapturedData[0].PSObject.Properties.Name | Should -Not -Contain 'path'
        $script:CapturedData[0].PSObject.Properties.Name | Should -Not -Contain 'name'
    }

    It 'honors minimum count input' {
        Mock -CommandName New-CIPPDbRequest -MockWith {
            @([pscustomobject]@{ ownerPrincipalName = 'a@contoso.com'; countOver260 = 3; countOver400 = 0 })
        }
        Get-CIPPAlertOneDriveLongPaths -TenantFilter 'contoso.onmicrosoft.com' -InputValue 10
        $script:CapturedData | Should -BeNullOrEmpty
    }

    It 'allowlists alert object properties' {
        Mock -CommandName New-CIPPDbRequest -MockWith {
            @([pscustomobject]@{ ownerPrincipalName = 'a@contoso.com'; countOver260 = 2; countOver400 = 0 })
        }
        Get-CIPPAlertOneDriveLongPaths -TenantFilter 'contoso.onmicrosoft.com'
        $Allowed = @('Message', 'Id', 'ownerPrincipalName', 'countOver260', 'countOver400', 'Tenant')
        foreach ($Name in $script:CapturedData[0].PSObject.Properties.Name) {
            $Allowed | Should -Contain $Name
        }
    }
}
