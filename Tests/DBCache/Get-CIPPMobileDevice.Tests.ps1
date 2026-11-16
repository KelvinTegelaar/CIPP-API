# Pester tests for Get-CIPPMobileDevice
# Devices are joined to their mailbox by the mailbox Name that starts each device Identity.

BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))

    function New-ExoRequest { param($tenantid, $cmdlet, $cmdParams, $Select, [switch]$StreamPages) }

    . (Join-Path $RepoRoot 'Modules/CIPPCore/Public/Get-CIPPMobileDevice.ps1')
}

Describe 'Get-CIPPMobileDevice' {
    BeforeEach {
        Mock New-ExoRequest { }
        Mock New-ExoRequest -ParameterFilter { $cmdlet -eq 'Get-MobileDevice' } {
            [pscustomobject]@{ Identity = 'b546d139\ExchangeActiveSyncDevices\Hx§Outlook§AAA'; DeviceId = 'AAA'; UserDisplayName = 'John'; DeviceAccessState = 'Blocked'; DeviceAccessStateReason = 'Individual'; FirstSyncTime = [datetime]'2023-05-02T20:34:43Z' }
            [pscustomobject]@{ Identity = 'b546d139\ExchangeActiveSyncDevices\Hx§Outlook§BBB'; DeviceId = 'BBB'; UserDisplayName = 'John'; DeviceAccessState = 'Quarantined'; DeviceAccessStateReason = 'Global' }
            [pscustomobject]@{ Identity = 'gone-mailbox\ExchangeActiveSyncDevices\CCC'; DeviceId = 'CCC'; UserDisplayName = 'Left'; DeviceAccessState = 'Allowed'; FriendlyName = 'Phone' }
        }
        Mock New-ExoRequest -ParameterFilter { $cmdlet -eq 'Get-CASMailbox' } {
            [pscustomobject]@{ Value = @(
                    [pscustomobject]@{ Name = 'other'; PrimarySmtpAddress = 'other@contoso.com'; ActiveSyncAllowedDeviceIDs = @(); ActiveSyncBlockedDeviceIDs = @() }
                    [pscustomobject]@{ Name = 'B546D139'; PrimarySmtpAddress = 'john@contoso.com'; ActiveSyncAllowedDeviceIDs = @('CCC'); ActiveSyncBlockedDeviceIDs = @('AAA') }
                ) }
        }
    }

    It 'resolves the mailbox address and the allow/block list entry per device' {
        $Devices = @(Get-CIPPMobileDevice -TenantFilter 'contoso.com')

        $Devices.Count | Should -Be 3
        $Devices[0].primarySmtpAddress | Should -Be 'john@contoso.com'
        $Devices[0].mailboxAccessList | Should -Be 'Blocked'
        $Devices[0].deviceAccessStateReason | Should -Be 'Individual'
        $Devices[0].firstSyncTime | Should -Be '2023-05-02T20:34:43Z'
        $Devices[1].mailboxAccessList | Should -BeNullOrEmpty
        $Devices[1].deviceAccessState | Should -Be 'Quarantined'
        $Devices[1].deviceFriendlyName | Should -Be 'Unknown'
    }

    It 'falls back to the mailbox name when no mailbox matches, and never reads another mailbox list' {
        $Device = @(Get-CIPPMobileDevice -TenantFilter 'contoso.com')[2]

        $Device.primarySmtpAddress | Should -Be 'gone-mailbox'
        $Device.mailboxAccessList | Should -BeNullOrEmpty
    }

    It 'skips the mailbox lookup when the tenant has no devices' {
        Mock New-ExoRequest -ParameterFilter { $cmdlet -eq 'Get-MobileDevice' } { }

        @(Get-CIPPMobileDevice -TenantFilter 'contoso.com').Count | Should -Be 0
        Should -Invoke New-ExoRequest -Times 0 -Exactly -ParameterFilter { $cmdlet -eq 'Get-CASMailbox' }
    }

    It 'carries no field that the cache would key on instead of the device identity' {
        $Device = @(Get-CIPPMobileDevice -TenantFilter 'contoso.com')[0]

        $Device.PSObject.Properties.Name | Should -Not -Contain 'ExternalDirectoryObjectId'
        $Device.PSObject.Properties.Name | Should -Not -Contain 'id'
        $Device.identity | Should -Be 'b546d139\ExchangeActiveSyncDevices\Hx§Outlook§AAA'
    }
}
