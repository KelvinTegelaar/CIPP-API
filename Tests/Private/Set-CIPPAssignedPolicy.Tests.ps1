# Pester tests for Set-CIPPAssignedPolicy error signalling.
#
# This function used to swallow every failure and return the error as a string. To a caller that
# only watches for an exception that is indistinguishable from success, which is how a policy whose
# assignment call failed still got recorded as correctly assigned by the Intune Template standard.
# A failure has to reach the caller as a failure.

BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))

    # Stubs mirror the real signatures so signature drift fails loudly here.
    function New-GraphGetRequest { [CmdletBinding()] param($uri, $tenantid, $AsApp, $ComplexFilter) }
    function New-GraphPOSTRequest { [CmdletBinding()] param($uri, $tenantid, $type, $body) }
    function Write-LogMessage { [CmdletBinding()] param($message, $tenant, $API, $tenantId, $headers, $user, $sev, $Sev2, $LogData) }
    function Get-CippException { [CmdletBinding()] param($Exception) }

    . (Join-Path $RepoRoot 'Modules/CIPPCore/Public/Get-CIPPIntuneAssignmentTarget.ps1')
    . (Join-Path $RepoRoot 'Modules/CIPPCore/Public/Set-CIPPAssignedPolicy.ps1')

    $script:Tenant = 'contoso.onmicrosoft.com'
    $script:SalesId = '11111111-1111-1111-1111-111111111111'
    $script:AllUsersGroupId = 'acacacac-9df4-4c7d-9d50-4ef0226f57a9'
}

Describe 'Set-CIPPAssignedPolicy' {
    BeforeEach {
        Mock -CommandName Write-LogMessage -MockWith { }
        Mock -CommandName Get-CippException -MockWith {
            [PSCustomObject]@{ NormalizedError = 'Graph said no' }
        }
        Mock -CommandName New-GraphGetRequest -ParameterFilter { $uri -like '*/groups?*' } -MockWith {
            @([PSCustomObject]@{ id = $script:SalesId; displayName = 'Sales Users' })
        }
        Mock -CommandName New-GraphGetRequest -ParameterFilter { $uri -like '*/assignments' } -MockWith { @() }
        Mock -CommandName New-GraphPOSTRequest -MockWith { @{} }
    }

    Context 'when the assignment succeeds' {
        It 'returns a result message and does not throw' {
            $Result = Set-CIPPAssignedPolicy -GroupName 'Sales Users' -PolicyId 'policy-1' -Type 'deviceConfigurations' -TenantFilter $script:Tenant

            $Result | Should -BeLike '*Successfully assigned*'
            Should -Invoke New-GraphPOSTRequest -Times 1 -Exactly
        }
    }

    Context 'when Graph rejects the assign call' {
        It 'throws instead of returning the error as a value' {
            Mock -CommandName New-GraphPOSTRequest -MockWith { throw 'Forbidden' }

            { Set-CIPPAssignedPolicy -GroupName 'Sales Users' -PolicyId 'policy-1' -Type 'deviceConfigurations' -TenantFilter $script:Tenant } |
                Should -Throw -ExpectedMessage '*Failed to assign*'
        }

        It 'still writes the failure to the audit log' {
            Mock -CommandName New-GraphPOSTRequest -MockWith { throw 'Forbidden' }

            { Set-CIPPAssignedPolicy -GroupName 'Sales Users' -PolicyId 'policy-1' -Type 'deviceConfigurations' -TenantFilter $script:Tenant } | Should -Throw

            Should -Invoke Write-LogMessage -Times 1 -Exactly -ParameterFilter { $Sev -eq 'Error' }
        }

        It 'surfaces the normalized error rather than the exception object' {
            Mock -CommandName New-GraphPOSTRequest -MockWith { throw 'Forbidden' }

            { Set-CIPPAssignedPolicy -GroupName 'Sales Users' -PolicyId 'policy-1' -Type 'deviceConfigurations' -TenantFilter $script:Tenant } |
                Should -Throw -ExpectedMessage '*Graph said no*'
        }
    }

    Context 'when the requested group does not exist' {
        It 'throws rather than reporting a successful no-op' {
            { Set-CIPPAssignedPolicy -GroupName 'Group That Was Renamed' -PolicyId 'policy-1' -Type 'deviceConfigurations' -TenantFilter $script:Tenant } |
                Should -Throw

            Should -Invoke New-GraphPOSTRequest -Times 0 -Exactly
        }
    }

    Context 'when existing assignments cannot be read in append mode' {
        It 'throws rather than posting a set that would drop them' {
            Mock -CommandName New-GraphGetRequest -ParameterFilter { $uri -like '*/assignments' } -MockWith {
                throw 'Throttled'
            }

            { Set-CIPPAssignedPolicy -GroupName 'Sales Users' -PolicyId 'policy-1' -Type 'deviceConfigurations' -TenantFilter $script:Tenant -AssignmentMode 'append' } |
                Should -Throw

            Should -Invoke New-GraphPOSTRequest -Times 0 -Exactly
        }
    }

    Context 'broad targets on a device management policy' {
        It 'sends the allLicensedUsers target' {
            $null = Set-CIPPAssignedPolicy -GroupName 'allLicensedUsers' -PolicyId 'policy-1' -Type 'deviceConfigurations' -TenantFilter $script:Tenant

            Should -Invoke New-GraphPOSTRequest -Times 1 -Exactly -ParameterFilter {
                ($body | ConvertFrom-Json).assignments.target.'@odata.type' -eq '#microsoft.graph.allLicensedUsersAssignmentTarget'
            }
        }
    }

    Context 'broad targets on an App Protection policy' {
        # The MAM service rejects any assign carrying a target class other than group/exclusion, so
        # the whole assignment fails - which is how a remediated policy ended up with none at all.
        It 'assigns all users as a group target on the All Users virtual group' {
            $null = Set-CIPPAssignedPolicy -GroupName 'allLicensedUsers' -PolicyId 'policy-1' -Type 'iosManagedAppProtections' -PlatformType 'deviceAppManagement' -TenantFilter $script:Tenant

            Should -Invoke New-GraphPOSTRequest -Times 1 -Exactly -ParameterFilter {
                $Sent = ($body | ConvertFrom-Json).assignments
                @($Sent).Count -eq 1 -and
                $Sent.target.'@odata.type' -eq '#microsoft.graph.groupAssignmentTarget' -and
                $Sent.target.groupId -eq $script:AllUsersGroupId
            }
        }

        It 'accepts the singular type name the policy lists expose' {
            $null = Set-CIPPAssignedPolicy -GroupName 'allLicensedUsers' -PolicyId 'policy-1' -Type 'androidManagedAppProtection' -PlatformType 'deviceAppManagement' -TenantFilter $script:Tenant

            Should -Invoke New-GraphPOSTRequest -Times 1 -Exactly -ParameterFilter {
                ($body | ConvertFrom-Json).assignments.target.groupId -eq $script:AllUsersGroupId
            }
        }

        It 'refuses All Devices instead of sending a target Graph will reject' {
            # Echo the real message rather than this file's fixed stand-in: the point of the guard
            # is that the operator is told why, not just that something failed.
            Mock -CommandName Get-CippException -MockWith { [PSCustomObject]@{ NormalizedError = $Exception.Exception.Message } }

            { Set-CIPPAssignedPolicy -GroupName 'AllDevices' -PolicyId 'policy-1' -Type 'iosManagedAppProtections' -PlatformType 'deviceAppManagement' -TenantFilter $script:Tenant } |
                Should -Throw -ExpectedMessage '*cannot be assigned to All Devices*'

            Should -Invoke New-GraphPOSTRequest -Times 0 -Exactly
        }

        It 'applies the users half of AllDevicesAndUsers rather than failing outright' {
            $null = Set-CIPPAssignedPolicy -GroupName 'AllDevicesAndUsers' -PolicyId 'policy-1' -Type 'iosManagedAppProtections' -PlatformType 'deviceAppManagement' -TenantFilter $script:Tenant

            Should -Invoke New-GraphPOSTRequest -Times 1 -Exactly -ParameterFilter {
                $Sent = ($body | ConvertFrom-Json).assignments
                @($Sent).Count -eq 1 -and $Sent.target.groupId -eq $script:AllUsersGroupId
            }
            Should -Invoke Write-LogMessage -Times 1 -Exactly -ParameterFilter { $sev -eq 'Warning' -and $message -like "*'All Devices'*" }
        }

        It 'still applies exclusions alongside the translated include target' {
            $null = Set-CIPPAssignedPolicy -GroupName 'allLicensedUsers' -ExcludeGroup 'Sales Users' -PolicyId 'policy-1' -Type 'iosManagedAppProtections' -PlatformType 'deviceAppManagement' -TenantFilter $script:Tenant

            Should -Invoke New-GraphPOSTRequest -Times 1 -Exactly -ParameterFilter {
                $Types = @(($body | ConvertFrom-Json).assignments.target.'@odata.type')
                $Types -contains '#microsoft.graph.groupAssignmentTarget' -and
                $Types -contains '#microsoft.graph.exclusionGroupAssignmentTarget'
            }
        }
    }

    Context 'WhatIf' {
        It 'does not post and does not throw' {
            $Result = Set-CIPPAssignedPolicy -GroupName 'Sales Users' -PolicyId 'policy-1' -Type 'deviceConfigurations' -TenantFilter $script:Tenant -WhatIf

            $Result | Should -BeNullOrEmpty
            Should -Invoke New-GraphPOSTRequest -Times 0 -Exactly
        }
    }
}
