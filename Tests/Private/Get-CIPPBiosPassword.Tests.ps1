# Pester tests for Get-CIPPBiosPassword
# This function returns a plaintext BIOS password, so two failure modes matter more than the happy
# path. First, the Graph URI must stay scoped to the one device: an unescaped $filter in the
# PowerShell string would silently request the tenant's entire hardwarePasswordDetails collection
# and hand back some other machine's password. Second, most Windows devices have no BIOS profile at
# all, so "no password" has to come back as a plain message rather than an error - that is the
# difference between a normal answer and a red toast on the majority of devices.

BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
    $FunctionPath = Join-Path $RepoRoot 'Modules/CIPPCore/Public/Get-CIPPBiosPassword.ps1'

    # Minimal stubs so Mock has commands to replace during tests
    function New-GraphGetRequest { param($uri, $tenantid) }
    function Write-LogMessage { param($headers, $API, $message, $Sev, $tenant, $LogData) }
    function Get-CippException { param($Exception) }

    . $FunctionPath
}

Describe 'Get-CIPPBiosPassword' {
    BeforeEach {
        $script:DeviceId = '11111111-2222-3333-4444-555555555555'
        $script:TenantFilter = 'contoso.onmicrosoft.com'

        Mock -CommandName Write-LogMessage -MockWith { }
        Mock -CommandName Get-CippException -MockWith {
            [PSCustomObject]@{ NormalizedError = 'Access denied' }
        }
        Mock -CommandName New-GraphGetRequest -MockWith {
            [PSCustomObject]@{
                id                = $script:DeviceId
                serialNumber      = 'ABC1234'
                currentPassword   = 'S3cretB105'
                previousPasswords = @('OldOne', 'OlderOne')
            }
        }
    }

    Context 'When the device has a managed BIOS password' {
        It 'returns the current password in copyField' {
            $Result = Get-CIPPBiosPassword -Device $script:DeviceId -TenantFilter $script:TenantFilter

            $Result.copyField | Should -Be 'S3cretB105'
            $Result.state | Should -Be 'success'
            $Result.resultText | Should -Match 'ABC1234'
        }

        It 'does not leak previous passwords into the result' {
            $Result = Get-CIPPBiosPassword -Device $script:DeviceId -TenantFilter $script:TenantFilter

            $Result.copyField | Should -Not -Match 'Old'
            $Result.resultText | Should -Not -Match 'Old'
        }

        It 'scopes the Graph request to the single device rather than the whole collection' {
            Get-CIPPBiosPassword -Device $script:DeviceId -TenantFilter $script:TenantFilter | Out-Null

            Should -Invoke New-GraphGetRequest -Times 1 -Exactly -ParameterFilter {
                $uri -eq "https://graph.microsoft.com/beta/deviceManagement/hardwarePasswordDetails?`$filter=id eq '$script:DeviceId'" -and
                $tenantid -eq $script:TenantFilter
            }
        }

        It 'audit logs the retrieval' {
            Get-CIPPBiosPassword -Device $script:DeviceId -TenantFilter $script:TenantFilter | Out-Null

            Should -Invoke Write-LogMessage -Times 1 -Exactly -ParameterFilter {
                $Sev -eq 'Info' -and $message -match 'Retrieved BIOS password'
            }
        }

        It 'takes the first record when Graph answers with a collection' {
            Mock -CommandName New-GraphGetRequest -MockWith {
                @(
                    [PSCustomObject]@{ id = $script:DeviceId; serialNumber = 'ABC1234'; currentPassword = 'S3cretB105' }
                    [PSCustomObject]@{ id = 'other'; serialNumber = 'ZZZ9999'; currentPassword = 'WrongOne' }
                )
            }

            $Result = Get-CIPPBiosPassword -Device $script:DeviceId -TenantFilter $script:TenantFilter

            $Result.copyField | Should -Be 'S3cretB105'
        }
    }

    Context 'When the device has no managed BIOS password' {
        It 'returns a message instead of throwing when Graph returns nothing' {
            Mock -CommandName New-GraphGetRequest -MockWith { }

            # A direct call, not a Should -Not -Throw scriptblock: an exception here fails the test
            # on its own, and this way the returned value is actually in scope to assert on.
            $Result = Get-CIPPBiosPassword -Device $script:DeviceId -TenantFilter $script:TenantFilter

            $Result | Should -BeOfType [string]
            $Result | Should -Match 'No BIOS password found'
        }

        It 'treats a record with an empty password as no password' {
            Mock -CommandName New-GraphGetRequest -MockWith {
                [PSCustomObject]@{ id = $script:DeviceId; serialNumber = 'ABC1234'; currentPassword = '' }
            }

            $Result = Get-CIPPBiosPassword -Device $script:DeviceId -TenantFilter $script:TenantFilter

            $Result | Should -Match 'No BIOS password found'
        }

        It 'logs the miss at Info, not Error' {
            Mock -CommandName New-GraphGetRequest -MockWith { }

            Get-CIPPBiosPassword -Device $script:DeviceId -TenantFilter $script:TenantFilter | Out-Null

            Should -Invoke Write-LogMessage -Times 1 -Exactly -ParameterFilter { $Sev -eq 'Info' }
            Should -Invoke Write-LogMessage -Times 0 -Exactly -ParameterFilter { $Sev -eq 'Error' }
        }
    }

    Context 'When the device ID is not a GUID' {
        # The ID is interpolated into an OData filter, so a value carrying a quote could close the
        # literal and widen the filter past the device the caller asked for.
        It 'rejects an ID that would break out of the filter literal, without calling Graph' {
            { Get-CIPPBiosPassword -Device "x' or id ne 'y" -TenantFilter $script:TenantFilter } |
                Should -Throw -ExpectedMessage '*Invalid device ID*'

            Should -Invoke New-GraphGetRequest -Times 0 -Exactly
        }

        It 'rejects an empty ID rather than querying the whole collection' {
            { Get-CIPPBiosPassword -Device '' -TenantFilter $script:TenantFilter } |
                Should -Throw -ExpectedMessage '*Invalid device ID*'

            Should -Invoke New-GraphGetRequest -Times 0 -Exactly
        }
    }

    Context 'When the Graph call fails' {
        BeforeEach {
            Mock -CommandName New-GraphGetRequest -MockWith { throw 'Forbidden' }
        }

        It 'throws so the endpoint answers with a 500 rather than a fake success' {
            { Get-CIPPBiosPassword -Device $script:DeviceId -TenantFilter $script:TenantFilter } |
                Should -Throw -ExpectedMessage '*Could not retrieve BIOS password*'
        }

        It 'logs the failure at Error with the normalized reason' {
            { Get-CIPPBiosPassword -Device $script:DeviceId -TenantFilter $script:TenantFilter } | Should -Throw

            Should -Invoke Write-LogMessage -Times 1 -Exactly -ParameterFilter {
                $Sev -eq 'Error' -and $message -match 'Access denied'
            }
        }
    }
}
