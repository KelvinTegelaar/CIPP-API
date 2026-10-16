# Pester tests for the Tenant External Recipient Rate Limit (TERRL) alert.
# Snoozes and alert lifecycle rows match items by Get-AlertContentHash, so a tenant that is still
# over its threshold must hash the same from run to run even as the observed volume moves hourly.

BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))

    function New-ExoRequest { param($tenantid, $cmdlet, $cmdParams) }
    function Get-CippException { param($Exception) }
    function Write-LogMessage { param($message, $API, $tenant, $sev, $LogData) }
    function Write-AlertTrace { param($cmdletName, $tenantFilter, $data) }

    . (Join-Path $RepoRoot 'Modules/CIPPCore/Public/GraphHelper/Get-AlertContentHash.ps1')
    . (Join-Path $RepoRoot 'Modules/CIPPAlerts/Public/Alerts/Get-CIPPAlertTERRL.ps1')
}

Describe 'TERRL alert content hash' {
    BeforeEach {
        $script:Captured = $null
        Mock Write-AlertTrace {
            param($cmdletName, $tenantFilter, $data)
            $script:Captured = @($data | Where-Object { $null -ne $_ })
        }
    }

    It 'keeps the item hash stable as the observed volume changes' {
        Mock New-ExoRequest { [pscustomobject]@{ ObservedValue = 850; Threshold = 1000; EnforcementEnabled = $true; Verdict = 'Allow' } }
        Get-CIPPAlertTERRL -InputValue 80 -TenantFilter 'contoso.onmicrosoft.com'
        $First = $script:Captured

        Mock New-ExoRequest { [pscustomobject]@{ ObservedValue = 910; Threshold = 1000; EnforcementEnabled = $true; Verdict = 'Allow' } }
        Get-CIPPAlertTERRL -InputValue 80 -TenantFilter 'contoso.onmicrosoft.com'
        $Second = $script:Captured

        $First.Count | Should -Be 1
        $Second.Count | Should -Be 1
        $First[0].UsagePercentage | Should -Be 85
        $Second[0].UsagePercentage | Should -Be 91
        $First[0].CurrentVolume | Should -Not -Be $Second[0].CurrentVolume
        (Get-AlertContentHash -AlertItem $Second[0]).ContentHash | Should -Be (Get-AlertContentHash -AlertItem $First[0]).ContentHash
    }

    It 'reports nothing while usage is under the threshold' {
        Mock New-ExoRequest { [pscustomobject]@{ ObservedValue = 100; Threshold = 1000; EnforcementEnabled = $true; Verdict = 'Allow' } }
        Get-CIPPAlertTERRL -InputValue 80 -TenantFilter 'contoso.onmicrosoft.com'
        $script:Captured.Count | Should -Be 0
        Should -Invoke Write-AlertTrace -Times 1 -Exactly
    }

    It 'falls back to an 80% threshold when no input is given' {
        Mock New-ExoRequest { [pscustomobject]@{ ObservedValue = 810; Threshold = 1000; EnforcementEnabled = $false; Verdict = 'Allow' } }
        Get-CIPPAlertTERRL -TenantFilter 'contoso.onmicrosoft.com'
        $script:Captured.Count | Should -Be 1
        $script:Captured[0].AlertThreshold | Should -Be 80
        $script:Captured[0].Message | Should -Be 'Tenant is above the 80% TERRL limit threshold'
    }
}
