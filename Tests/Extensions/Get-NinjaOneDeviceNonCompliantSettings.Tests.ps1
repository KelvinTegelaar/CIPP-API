BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))

    function New-GraphBulkRequest { param($Requests, $tenantid) }

    . (Join-Path $RepoRoot 'Modules/CippExtensions/Public/NinjaOne/Get-NinjaOneDeviceNonCompliantSettings.ps1')
}

Describe 'Get-NinjaOneDeviceNonCompliantSettings' {
    It 'returns nothing and skips Graph when no device ids are given' {
        Mock New-GraphBulkRequest { @() }

        $Result = Get-NinjaOneDeviceNonCompliantSettings -TenantFilter 'contoso.onmicrosoft.com' -ManagedDeviceIds @()

        $Result.Count | Should -Be 0
        Should -Invoke New-GraphBulkRequest -Times 0 -Exactly
    }

    It 'lists the failing settings per device, once per setting, with the state appended for errors' {
        Mock New-GraphBulkRequest -ParameterFilter { $Requests[0].url -like '*deviceCompliancePolicyStates' } {
            @(
                [pscustomobject]@{
                    id     = 'dev-1'
                    status = 200
                    body   = [pscustomobject]@{
                        value = @(
                            [pscustomobject]@{ id = 'pol-a'; displayName = 'Windows Compliance'; state = 'nonCompliant' },
                            [pscustomobject]@{ id = 'pol-b'; displayName = 'Default Device Compliance Policy'; state = 'compliant' },
                            [pscustomobject]@{ id = 'pol-c'; displayName = 'Broken Policy'; state = 'error' }
                        )
                    }
                },
                [pscustomobject]@{
                    id     = 'dev-2'
                    status = 200
                    body   = [pscustomobject]@{ value = @([pscustomobject]@{ id = 'pol-a'; displayName = 'Windows Compliance'; state = 'compliant' }) }
                }
            )
        }
        Mock New-GraphBulkRequest -ParameterFilter { $Requests[0].url -like '*settingStates' } {
            @(
                [pscustomobject]@{
                    id     = 'dev-1|pol-a'
                    status = 200
                    body   = [pscustomobject]@{
                        value = @(
                            [pscustomobject]@{ setting = 'Windows10CompliancePolicy.BitLockerEnabled'; settingName = 'BitLocker'; state = 'nonCompliant'; userPrincipalName = 'a@contoso.com' },
                            [pscustomobject]@{ setting = 'Windows10CompliancePolicy.BitLockerEnabled'; settingName = 'BitLocker'; state = 'nonCompliant'; userPrincipalName = 'b@contoso.com' },
                            [pscustomobject]@{ setting = 'Windows10CompliancePolicy.OsMinimumVersion'; settingName = 'Minimum OS version'; state = 'compliant' }
                        )
                    }
                },
                [pscustomobject]@{
                    id     = 'dev-1|pol-c'
                    status = 200
                    body   = [pscustomobject]@{ value = @([pscustomobject]@{ setting = 'Windows10CompliancePolicy.PasswordRequired'; state = 'error' }) }
                }
            )
        }

        $Result = Get-NinjaOneDeviceNonCompliantSettings -TenantFilter 'contoso.onmicrosoft.com' -ManagedDeviceIds @('dev-1', 'dev-2', 'dev-1')

        @($Result.Keys) | Should -Be @('dev-1')
        $Result['dev-1'] | Should -Be "Windows Compliance: BitLocker`nBroken Policy: Windows10CompliancePolicy.PasswordRequired (error)"
        Should -Invoke New-GraphBulkRequest -Times 1 -Exactly -ParameterFilter { $Requests.Count -eq 2 -and $Requests[0].url -like '*deviceCompliancePolicyStates' }
        Should -Invoke New-GraphBulkRequest -Times 1 -Exactly -ParameterFilter { $Requests.Count -eq 2 -and $Requests[0].url -eq "/deviceManagement/managedDevices('dev-1')/deviceCompliancePolicyStates/pol-a/settingStates" }
    }

    It 'does not fetch setting states when every policy state is compliant' {
        Mock New-GraphBulkRequest {
            @([pscustomobject]@{ id = 'dev-1'; status = 200; body = [pscustomobject]@{ value = @([pscustomobject]@{ id = 'pol-a'; displayName = 'P'; state = 'compliant' }) } })
        }

        $Result = Get-NinjaOneDeviceNonCompliantSettings -TenantFilter 'contoso.onmicrosoft.com' -ManagedDeviceIds @('dev-1')

        $Result.Count | Should -Be 0
        Should -Invoke New-GraphBulkRequest -Times 1 -Exactly
    }

    It 'skips a device whose policy state lookup failed and still reports the others' {
        Mock New-GraphBulkRequest -ParameterFilter { $Requests[0].url -like '*deviceCompliancePolicyStates' } {
            @(
                [pscustomobject]@{ id = 'dev-gone'; status = 404; body = [pscustomobject]@{ error = [pscustomobject]@{ message = 'Not found' } } },
                [pscustomobject]@{ id = 'dev-1'; status = 200; body = [pscustomobject]@{ value = @([pscustomobject]@{ id = 'pol-a'; displayName = 'P'; state = 'nonCompliant' }) } }
            )
        }
        Mock New-GraphBulkRequest -ParameterFilter { $Requests[0].url -like '*settingStates' } {
            @([pscustomobject]@{ id = 'dev-1|pol-a'; status = 200; body = [pscustomobject]@{ value = @([pscustomobject]@{ settingName = 'Firewall'; state = 'nonCompliant' }) } })
        }

        $Result = Get-NinjaOneDeviceNonCompliantSettings -TenantFilter 'contoso.onmicrosoft.com' -ManagedDeviceIds @('dev-gone', 'dev-1') -WarningAction SilentlyContinue

        @($Result.Keys) | Should -Be @('dev-1')
        $Result['dev-1'] | Should -Be 'P: Firewall'
    }
}
