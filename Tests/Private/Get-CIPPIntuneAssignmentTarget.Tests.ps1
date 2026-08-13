# Pester tests for Get-CIPPIntuneAssignmentTarget.
#
# Intune's MAM service, which serves App Protection and managed app configuration, accepts only
# group targets - an assign carrying allLicensedUsersAssignmentTarget or allDevicesAssignmentTarget
# is rejected outright. This is the one place that difference is expressed, because both the
# assignment write and the assignment comparison read it from here.

BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
    . (Join-Path $RepoRoot 'Modules/CIPPCore/Public/Get-CIPPIntuneAssignmentTarget.ps1')

    $script:AllUsersGroupId = 'acacacac-9df4-4c7d-9d50-4ef0226f57a9'
}

Describe 'Get-CIPPIntuneAssignmentTarget' {

    Context 'device management policy types' {
        It 'uses the broad targets for <AssignTo>' -ForEach @(
            @{ AssignTo = 'allLicensedUsers'; Expected = @('#microsoft.graph.allLicensedUsersAssignmentTarget') }
            @{ AssignTo = 'AllDevices'; Expected = @('#microsoft.graph.allDevicesAssignmentTarget') }
            @{ AssignTo = 'AllDevicesAndUsers'; Expected = @('#microsoft.graph.allDevicesAssignmentTarget', '#microsoft.graph.allLicensedUsersAssignmentTarget') }
        ) {
            $Result = Get-CIPPIntuneAssignmentTarget -AssignTo $AssignTo -PolicyType 'deviceConfigurations'

            @($Result.Targets | ForEach-Object { $_.'@odata.type' }) | Should -Be $Expected
            $Result.Unsupported | Should -BeNullOrEmpty
            $Result.Dropped | Should -BeNullOrEmpty
        }

        It 'produces no broad target for <AssignTo>, which the caller resolves itself' -ForEach @(
            @{ AssignTo = 'customGroup' }
            @{ AssignTo = 'On' }
            @{ AssignTo = '' }
        ) {
            $Result = Get-CIPPIntuneAssignmentTarget -AssignTo $AssignTo -PolicyType 'deviceConfigurations'

            $Result.Targets | Should -BeNullOrEmpty
            $Result.Unsupported | Should -BeNullOrEmpty
        }
    }

    Context 'MAM policy types' {
        It 'recognises <PolicyType> as MAM' -ForEach @(
            @{ PolicyType = 'AppProtection' }
            @{ PolicyType = 'managedAppPolicies' }
            @{ PolicyType = 'iosManagedAppProtections' }
            @{ PolicyType = 'androidManagedAppProtections' }
            @{ PolicyType = 'windowsManagedAppProtections' }
            @{ PolicyType = 'targetedManagedAppConfigurations' }
        ) {
            (Get-CIPPIntuneAssignmentTarget -AssignTo 'allLicensedUsers' -PolicyType $PolicyType).IsMam |
                Should -BeTrue
        }

        It 'does not treat device-side app configuration as MAM' {
            # mobileAppConfigurations targets enrolled devices and goes through device management.
            (Get-CIPPIntuneAssignmentTarget -AssignTo 'allLicensedUsers' -PolicyType 'mobileAppConfigurations').IsMam |
                Should -BeFalse
        }

        It 'expresses all users as a group assignment on the All Users virtual group' {
            $Result = Get-CIPPIntuneAssignmentTarget -AssignTo 'allLicensedUsers' -PolicyType 'iosManagedAppProtections'

            @($Result.Targets).Count | Should -Be 1
            $Result.Targets[0].'@odata.type' | Should -Be '#microsoft.graph.groupAssignmentTarget'
            $Result.Targets[0].groupId | Should -Be $script:AllUsersGroupId
            $Result.Unsupported | Should -BeNullOrEmpty
        }

        It 'names the virtual group so it is not reported as a bare GUID' {
            $Result = Get-CIPPIntuneAssignmentTarget -AssignTo 'allLicensedUsers' -PolicyType 'iosManagedAppProtections'

            $Result.GroupNames[$script:AllUsersGroupId] | Should -Be 'All Users'
        }

        It 'reports All Devices as unsupported rather than guessing an audience' {
            $Result = Get-CIPPIntuneAssignmentTarget -AssignTo 'AllDevices' -PolicyType 'iosManagedAppProtections'

            $Result.Targets | Should -BeNullOrEmpty
            $Result.Unsupported | Should -BeLike '*cannot be assigned to All Devices*'
        }

        It 'keeps the users half of AllDevicesAndUsers and reports the dropped half' {
            $Result = Get-CIPPIntuneAssignmentTarget -AssignTo 'AllDevicesAndUsers' -PolicyType 'androidManagedAppProtections'

            @($Result.Targets).Count | Should -Be 1
            $Result.Targets[0].groupId | Should -Be $script:AllUsersGroupId
            $Result.Unsupported | Should -BeNullOrEmpty
            $Result.Dropped | Should -Be @('All Devices')
        }

        It 'emits no allLicensedUsers or allDevices target for any option' {
            foreach ($AssignTo in 'allLicensedUsers', 'AllDevices', 'AllDevicesAndUsers') {
                $Result = Get-CIPPIntuneAssignmentTarget -AssignTo $AssignTo -PolicyType 'iosManagedAppProtections'
                @($Result.Targets | ForEach-Object { $_.'@odata.type' }) |
                    Should -Not -Contain '#microsoft.graph.allLicensedUsersAssignmentTarget'
                @($Result.Targets | ForEach-Object { $_.'@odata.type' }) |
                    Should -Not -Contain '#microsoft.graph.allDevicesAssignmentTarget'
            }
        }
    }

    Context 'Device Preparation profiles' {
        # Device Preparation deployments start when an assigned user signs in during OOBE, so the
        # assignment surface is user groups only - the broad virtual targets leave the profile
        # without an effective assignment even when Graph accepts the assign call.

        It 'expresses the users half of AllDevicesAndUsers as a group assignment on the All Users virtual group' {
            $Result = Get-CIPPIntuneAssignmentTarget -AssignTo 'AllDevicesAndUsers' -PolicyType 'DevicePrepProfile'

            @($Result.Targets).Count | Should -Be 1
            $Result.Targets[0].'@odata.type' | Should -Be '#microsoft.graph.groupAssignmentTarget'
            $Result.Targets[0].groupId | Should -Be $script:AllUsersGroupId
            $Result.Unsupported | Should -BeNullOrEmpty
            $Result.Dropped | Should -Be @('All Devices')
        }

        It 'reports All Devices as unsupported rather than writing a target that never triggers' {
            $Result = Get-CIPPIntuneAssignmentTarget -AssignTo 'AllDevices' -PolicyType 'DevicePrepProfile'

            $Result.Targets | Should -BeNullOrEmpty
            $Result.Unsupported | Should -BeLike '*cannot be assigned to All Devices*'
        }

        It 'names the virtual group so it is not reported as a bare GUID' {
            $Result = Get-CIPPIntuneAssignmentTarget -AssignTo 'AllDevicesAndUsers' -PolicyType 'DevicePrepProfile'

            $Result.GroupNames[$script:AllUsersGroupId] | Should -Be 'All Users'
        }

        It 'is not treated as MAM' {
            (Get-CIPPIntuneAssignmentTarget -AssignTo 'allLicensedUsers' -PolicyType 'DevicePrepProfile').IsMam |
                Should -BeFalse
        }
    }
}
