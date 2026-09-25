BeforeAll {
    . "$PSScriptRoot/../../Modules/CippExtensions/Public/Hudu/Find-HuduDeviceMatch.ps1"

    function New-TestHuduDevice {
        param($Id, $Name, $Serial, $ManageName, $ManageSerial)
        [PSCustomObject]@{
            id             = $Id
            name           = $Name
            primary_serial = $Serial
            cards          = @(
                [PSCustomObject]@{
                    integrator_name = 'cw_manage'
                    data            = [PSCustomObject]@{
                        name         = $ManageName
                        serialNumber = $ManageSerial
                    }
                }
            )
        }
    }
}

Describe 'Find-HuduDeviceMatch' {
    BeforeEach {
        $HuduDevices = @(
            New-TestHuduDevice -Id 1 -Name 'DEVICE-01' -Serial '' -ManageName @('DEVICE-01') -ManageSerial ''
            New-TestHuduDevice -Id 2 -Name 'RENAMED-DEVICE' -Serial 'SERIAL-02' -ManageName @('OLD-NAME') -ManageSerial 'CW-SERIAL-02'
        )
    }

    It 'does not match an unrelated asset through a blank serial number' {
        $Result = @(Find-HuduDeviceMatch -Device @{ deviceName = 'UNKNOWN'; serialNumber = '' } -HuduDevices $HuduDevices)
        $Result | Should -BeNullOrEmpty
    }

    It 'matches a blank-serial device by name' {
        $Result = @(Find-HuduDeviceMatch -Device @{ deviceName = 'DEVICE-01'; serialNumber = '' } -HuduDevices $HuduDevices)
        $Result.id | Should -Be 1
    }

    It 'prefers a valid serial match over the name' {
        $Result = @(Find-HuduDeviceMatch -Device @{ deviceName = 'DEVICE-01'; serialNumber = 'SERIAL-02' } -HuduDevices $HuduDevices)
        $Result.id | Should -Be 2
    }

    It 'matches a ConnectWise Manage serial' {
        $Result = @(Find-HuduDeviceMatch -Device @{ deviceName = 'UNKNOWN'; serialNumber = 'CW-SERIAL-02' } -HuduDevices $HuduDevices)
        $Result.id | Should -Be 2
    }

    It 'falls back to the name when a usable serial does not match' {
        $Result = @(Find-HuduDeviceMatch -Device @{ deviceName = 'DEVICE-01'; serialNumber = 'NO-MATCH' } -HuduDevices $HuduDevices)
        $Result.id | Should -Be 1
    }

    It 'uses the name for an excluded serial' {
        $Result = @(Find-HuduDeviceMatch -Device @{ deviceName = 'DEVICE-01'; serialNumber = 'DEFAULT-SERIAL' } -HuduDevices $HuduDevices -ExcludeSerials 'DEFAULT-SERIAL')
        $Result.id | Should -Be 1
    }

    It 'returns every duplicate match so the caller can reject ambiguity' {
        $HuduDevices += New-TestHuduDevice -Id 3 -Name 'DEVICE-01' -Serial 'OTHER' -ManageName @() -ManageSerial 'OTHER'
        $Result = @(Find-HuduDeviceMatch -Device @{ deviceName = 'DEVICE-01'; serialNumber = '' } -HuduDevices $HuduDevices)
        $Result.Count | Should -Be 2
        $Result.id | Should -Be 1, 3
    }
}
