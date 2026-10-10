BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
    function New-GraphGetRequest { param($uri, $tenantid, $AsApp) }
    . (Join-Path $RepoRoot 'Modules/CIPPCore/Public/BEC/New-CIPPBecCollectorResult.ps1')
    . (Join-Path $RepoRoot 'Modules/CIPPCore/Public/BEC/Get-CIPPBecRegisteredDevices.ps1')
    $script:UserId = 'c0ffee00-0000-4000-8000-000000000001'
    $script:Start = [datetime]::new(2026, 8, 20, 0, 0, 0, [System.DateTimeKind]::Utc)

    function Get-DeviceFixture {
        param([string]$Id, $Registered = $null, [string]$Name = 'DESKTOP-01')
        [pscustomobject]@{
            id                            = $Id
            deviceId                      = "dev-$Id"
            displayName                   = $Name
            operatingSystem               = 'Windows'
            operatingSystemVersion        = '10.0.26100.1'
            trustType                     = 'AzureAd'
            registrationDateTime          = $Registered
            approximateLastSignInDateTime = '2026-08-25T06:00:00Z'
            accountEnabled                = $true
            isCompliant                   = $false
            isManaged                     = $true
            profileType                   = 'RegisteredDevice'
            enrollmentType                = 'AzureADJoin'
            manufacturer                  = 'Dell Inc.'
            model                         = 'Latitude 5450'
        }
    }
}

Describe 'Get-CIPPBecRegisteredDevices' {
    BeforeEach {
        Mock New-GraphGetRequest { @($script:Devices) }
        $script:Devices = @()
    }

    It 'reads the user''s registered devices app-only with the device projection' {
        $null = Get-CIPPBecRegisteredDevices -TenantFilter 'contoso.com' -UserId $script:UserId -StartDate $script:Start
        Should -Invoke New-GraphGetRequest -Times 1 -ParameterFilter {
            $uri -like "https://graph.microsoft.com/v1.0/users/$($script:UserId)/registeredDevices/microsoft.graph.device?`$select=id,deviceId,*" -and
            $uri -match 'registrationDateTime' -and $uri -match 'approximateLastSignInDateTime' -and
            $tenantid -eq 'contoso.com' -and $AsApp -eq $true
        }
    }

    It 'projects a device row with UTC timestamps and no cap' {
        $script:Devices = @(Get-DeviceFixture -Id 'd1' -Registered '2026-08-21T12:00:00+02:00')
        $Result = Get-CIPPBecRegisteredDevices -TenantFilter 'contoso.com' -UserId $script:UserId -StartDate $script:Start
        $Result.Complete | Should -BeTrue
        $Result.Cap | Should -BeNullOrEmpty
        $Result.Error | Should -BeNullOrEmpty
        $Result.Count | Should -Be 1
        $Row = $Result.Data[0]
        $Row.id | Should -Be 'd1'
        $Row.deviceId | Should -Be 'dev-d1'
        $Row.displayName | Should -Be 'DESKTOP-01'
        $Row.operatingSystem | Should -Be 'Windows'
        $Row.operatingSystemVersion | Should -Be '10.0.26100.1'
        $Row.trustType | Should -Be 'AzureAd'
        $Row.profileType | Should -Be 'RegisteredDevice'
        $Row.enrollmentType | Should -Be 'AzureADJoin'
        $Row.manufacturer | Should -Be 'Dell Inc.'
        $Row.model | Should -Be 'Latitude 5450'
        $Row.accountEnabled | Should -BeTrue
        $Row.isCompliant | Should -BeFalse
        $Row.isManaged | Should -BeTrue
        $Row.registrationDateTime | Should -Be '2026-08-21T10:00:00Z' -Because 'the offset is folded into UTC'
        $Row.approximateLastSignInDateTime | Should -Be '2026-08-25T06:00:00Z'
        $Row.RegisteredInWindow | Should -BeTrue
    }

    It 'flags registrations at or after the window start, sorts them first and skips rows without an id' {
        $script:Devices = @(
            Get-DeviceFixture -Id 'd-old' -Registered '2026-08-19T23:59:59Z'
            Get-DeviceFixture -Id 'd-edge' -Registered '2026-08-20T00:00:00Z'
            Get-DeviceFixture -Id 'd-new' -Registered '2026-08-22T00:00:00Z'
            Get-DeviceFixture -Id 'd-none'
            Get-DeviceFixture -Id $null -Registered '2026-08-23T00:00:00Z'
        )
        $Result = Get-CIPPBecRegisteredDevices -TenantFilter 'contoso.com' -UserId $script:UserId -StartDate $script:Start
        $Result.Count | Should -Be 4
        $Result.Data[0].id | Should -Be 'd-new' -Because 'in-window registrations sort first, newest first'
        $Result.Data[1].id | Should -Be 'd-edge' -Because 'a registration exactly at the window start is inside the window'
        $Result.Data[1].RegisteredInWindow | Should -BeTrue
        $Old = $Result.Data | Where-Object { $_.id -eq 'd-old' }
        $Old.RegisteredInWindow | Should -BeFalse -Because 'one second before the window start is outside it'
        $Old.registrationDateTime | Should -Be '2026-08-19T23:59:59Z'
        $None = $Result.Data | Where-Object { $_.id -eq 'd-none' }
        $None.RegisteredInWindow | Should -BeOfType [bool]
        $None.RegisteredInWindow | Should -BeFalse
        $None.registrationDateTime | Should -BeNullOrEmpty
    }

    It 'returns an empty complete result when Graph returns nothing' {
        Mock New-GraphGetRequest { }
        $Result = Get-CIPPBecRegisteredDevices -TenantFilter 'contoso.com' -UserId $script:UserId -StartDate $script:Start
        $Result.Complete | Should -BeTrue
        $Result.Count | Should -Be 0
        @($Result.Data).Count | Should -Be 0
    }

    It 'lets a Graph failure propagate to the caller instead of reporting an empty device list' {
        Mock New-GraphGetRequest { throw 'Graph unavailable' }
        { Get-CIPPBecRegisteredDevices -TenantFilter 'contoso.com' -UserId $script:UserId -StartDate $script:Start } | Should -Throw -ExpectedMessage '*Graph unavailable*'
    }
}
