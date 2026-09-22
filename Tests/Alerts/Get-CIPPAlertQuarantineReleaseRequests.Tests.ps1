# Pester tests for Get-CIPPAlertQuarantineReleaseRequests
#
# The alert queries Exchange Online (Get-QuarantineMessage) for messages whose ReleaseStatus is
# 'Requested' and emits them through Write-AlertTrace. The regression these tests guard against:
# the received-date window used to be only 6 hours, which silently hid every release request raised
# against a message that had been sitting in quarantine longer than that - even though the same
# request is plainly visible on the Quarantine page (which applies no received-date filter).

BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
    $AlertPath = Join-Path $RepoRoot 'Modules/CIPPAlerts/Public/Alerts/Get-CIPPAlertQuarantineReleaseRequests.ps1'
    if (-not (Test-Path $AlertPath)) { throw "Could not locate Get-CIPPAlertQuarantineReleaseRequests.ps1 at $AlertPath" }

    function Test-CIPPStandardLicense { [CmdletBinding()] param($StandardName, $TenantFilter, $Preset) }
    function New-ExoRequest { [CmdletBinding()] param($tenantid, $cmdlet, $cmdParams) }
    function Get-CippTable { [CmdletBinding()] param($tablename) }
    function Get-CIPPAzDataTableEntity { [CmdletBinding()] param($Filter) }
    function Write-AlertTrace { [CmdletBinding()] param($cmdletName, $tenantFilter, $data) }
    function Write-LogMessage { [CmdletBinding()] param($API, $tenant, $message, $sev, $LogData) }
    function Get-CippException { [CmdletBinding()] param($Exception) [pscustomobject]@{ NormalizedError = "$Exception" } }

    . $AlertPath

    $script:Tenant = 'contoso.onmicrosoft.com'
}

Describe 'Get-CIPPAlertQuarantineReleaseRequests' {
    BeforeEach {
        $script:CapturedParams = $null
        $script:CapturedData = $null
        $script:CapturedTenant = $null
        $script:CapturedErrorMessage = $null

        Mock -CommandName Test-CIPPStandardLicense -MockWith { $true }
        Mock -CommandName Get-CippTable -MockWith { @{} }
        Mock -CommandName Get-CIPPAzDataTableEntity -MockWith { [pscustomobject]@{ Value = 'cipp.contoso.com' } }
        Mock -CommandName Write-LogMessage -MockWith {
            param($API, $tenant, $message, $sev, $LogData)
            $script:CapturedErrorMessage = $message
        }
        Mock -CommandName Write-AlertTrace -MockWith {
            param($cmdletName, $tenantFilter, $data)
            $script:CapturedData = $data
            $script:CapturedTenant = $tenantFilter
        }

        # One pending release request against a message received well outside a 6-hour window.
        Mock -CommandName New-ExoRequest -MockWith {
            param($tenantid, $cmdlet, $cmdParams)
            $script:CapturedParams = $cmdParams
            [pscustomobject]@{
                Identity         = 'msg-1'
                MessageId        = '<abc@contoso.com>'
                Subject          = 'Suspicious invoice'
                SenderAddress    = 'attacker@evil.example'
                RecipientAddress = @('victim@contoso.com')
                Type             = 'Phish'
                PolicyName       = 'Default'
                ReleaseStatus    = 'Requested'
                ReceivedTime     = (Get-Date).AddHours(-18)
            }
        }
    }

    It 'queries a one-day window, not a few hours' {
        Get-CIPPAlertQuarantineReleaseRequests -TenantFilter $script:Tenant

        $script:CapturedParams | Should -Not -BeNullOrEmpty
        $script:CapturedParams.ReleaseStatus | Should -Be 'Requested'
        $Span = ((Get-Date) - $script:CapturedParams.StartReceivedDate).TotalDays
        $Span | Should -BeGreaterThan 0.9   # ~1 day
        $Span | Should -BeLessThan 1.1       # regression guard: the old window was 0.25 days (6 hours)
        $script:CapturedParams.EndReceivedDate | Should -BeGreaterThan $script:CapturedParams.StartReceivedDate
    }

    It 'emits the pending release request through the alert pipeline' {
        Get-CIPPAlertQuarantineReleaseRequests -TenantFilter $script:Tenant

        $script:CapturedTenant | Should -Be $script:Tenant
        $script:CapturedData | Should -Not -BeNullOrEmpty
        @($script:CapturedData).Count | Should -Be 1
        $script:CapturedData[0].Subject | Should -Be 'Suspicious invoice'
        $script:CapturedData[0].ReleaseStatus | Should -Be 'Requested'
        $script:CapturedData[0].RecipientAddress | Should -Be 'victim@contoso.com'
        $script:CapturedData[0].Tenant | Should -Be $script:Tenant
        $script:CapturedData[0].QuarantineViewUrl | Should -Match 'https://cipp.contoso.com/email/administration/quarantine'
    }

    It 'does not emit when there are no pending release requests' {
        Mock -CommandName New-ExoRequest -MockWith { param($tenantid, $cmdlet, $cmdParams) $script:CapturedParams = $cmdParams; @() }

        Get-CIPPAlertQuarantineReleaseRequests -TenantFilter $script:Tenant

        Should -Invoke Write-AlertTrace -Times 0
        $script:CapturedData | Should -BeNullOrEmpty
    }

    It 'skips processing when the tenant is not licensed for Exchange' {
        Mock -CommandName Test-CIPPStandardLicense -MockWith { $false }

        Get-CIPPAlertQuarantineReleaseRequests -TenantFilter $script:Tenant

        Should -Invoke New-ExoRequest -Times 0
        Should -Invoke Write-AlertTrace -Times 0
    }

    It 'logs an error and does not emit when the quarantine query fails' {
        Mock -CommandName New-ExoRequest -MockWith { throw 'EXO unavailable' }

        Get-CIPPAlertQuarantineReleaseRequests -TenantFilter $script:Tenant

        Should -Invoke Write-AlertTrace -Times 0
        $script:CapturedErrorMessage | Should -Match 'QuarantineReleaseRequests'
        $script:CapturedErrorMessage | Should -Match 'EXO unavailable'
    }
}
