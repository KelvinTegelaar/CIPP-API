BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
    . (Join-Path $RepoRoot 'Modules/CIPPCore/Public/Get-CIPPIntunePolicyListDefinitions.ps1')
    . (Join-Path $RepoRoot 'Modules/CIPPCore/Public/ConvertTo-CIPPIntunePolicyListItem.ps1')
}

Describe 'Intune policy list helpers' {
    It 'defines the same twelve policy families for live and cached views' {
        $Definitions = @(Get-CIPPIntunePolicyListDefinitions)

        $Definitions | Should -HaveCount 12
        $Definitions.Id | Should -Be @(
            'DeviceConfigurations'
            'WindowsDriverUpdateProfiles'
            'WindowsFeatureUpdateProfiles'
            'windowsQualityUpdatePolicies'
            'windowsQualityUpdateProfiles'
            'hardwareConfigurations'
            'GroupPolicyConfigurations'
            'MobileAppConfigurations'
            'ConfigurationPolicies'
            'deviceCompliancePolicies'
            'Intents'
            'ManagedAppPolicies'
        )
        $Definitions.CacheType | Should -Contain 'IntuneDeviceCompliancePolicies'
        $Definitions.CacheType | Should -Contain 'IntuneIntents'
        $Definitions.CacheType | Should -Contain 'IntuneAppProtectionPolicies'
        ($Definitions | Where-Object Id -eq 'ManagedAppPolicies').FetchAssignments | Should -BeFalse
    }

    It 'uses the correct mobile app management resource and live OEMConfig filter' {
        $Definition = Get-CIPPIntunePolicyListDefinitions | Where-Object Id -eq 'MobileAppConfigurations'

        $Definition.GraphUri | Should -Be '/deviceAppManagement/mobileAppConfigurations?$expand=assignments&$filter=microsoft.graph.androidManagedStoreAppConfiguration/appSupportsOemConfig%20eq%20true'
        $Definition.CacheUri | Should -Be $Definition.GraphUri
    }

    It 'normalizes assignments and policy labels consistently' {
        $Policy = [PSCustomObject]@{
            id                          = 'policy-1'
            displayName                 = 'Policy One'
            'assignments@odata.context' = 'https://graph.microsoft.com/beta/$metadata#deviceManagement/configurationPolicies/assignments'
            assignments                 = @(
                [PSCustomObject]@{
                    target = [PSCustomObject]@{
                        '@odata.type' = '#microsoft.graph.groupAssignmentTarget'
                        groupId       = 'group-1'
                    }
                }
                [PSCustomObject]@{
                    target = [PSCustomObject]@{
                        '@odata.type' = '#microsoft.graph.exclusionGroupAssignmentTarget'
                        groupId       = 'group-2'
                    }
                }
            )
        }

        $Result = ConvertTo-CIPPIntunePolicyListItem -Policy $Policy -URLName 'ConfigurationPolicies' -DefaultPolicyTypeName 'Device Configuration' -GroupLookup @{
            'group-1' = 'Included Group'
            'group-2' = 'Excluded Group'
        }

        $Result.PolicyTypeName | Should -Be 'Device Configuration'
        $Result.URLName | Should -Be 'ConfigurationPolicies'
        $Result.PolicyAssignment | Should -Be 'Included Group'
        $Result.PolicyExclude | Should -Be 'Excluded Group'
    }

    It 'accepts and skips an explicit null policy' {
        $Result = ConvertTo-CIPPIntunePolicyListItem -Policy $null -URLName 'ConfigurationPolicies' -DefaultPolicyTypeName 'Device Configuration'

        $Result | Should -BeNullOrEmpty
    }

    It 'tolerates group assignment targets without a group ID' {
        $Policy = [PSCustomObject]@{
            id          = 'malformed-assignments'
            displayName = 'Malformed assignments'
            assignments = @(
                [PSCustomObject]@{
                    target = [PSCustomObject]@{
                        '@odata.type' = '#microsoft.graph.groupAssignmentTarget'
                    }
                }
                [PSCustomObject]@{
                    target = [PSCustomObject]@{
                        '@odata.type' = '#microsoft.graph.exclusionGroupAssignmentTarget'
                        groupId       = ''
                    }
                }
            )
        }

        { $script:MalformedAssignmentResult = ConvertTo-CIPPIntunePolicyListItem -Policy $Policy -URLName 'ConfigurationPolicies' -DefaultPolicyTypeName 'Device Configuration' } |
            Should -Not -Throw
        $script:MalformedAssignmentResult.PolicyAssignment | Should -Be ''
        $script:MalformedAssignmentResult.PolicyExclude | Should -Be ''
    }

    It 'labels each managed app protection platform' -ForEach @(
        @{ ODataType = '#microsoft.graph.iosManagedAppProtection'; Expected = 'iOS App Protection' }
        @{ ODataType = '#microsoft.graph.androidManagedAppProtection'; Expected = 'Android App Protection' }
        @{ ODataType = '#microsoft.graph.windowsManagedAppProtection'; Expected = 'Windows App Protection' }
    ) {
        $Policy = [PSCustomObject]@{
            id            = 'managed-policy'
            displayName   = 'Managed policy'
            '@odata.type' = $ODataType
        }

        $Result = ConvertTo-CIPPIntunePolicyListItem -Policy $Policy -URLName 'ManagedAppPolicies' -DefaultPolicyTypeName 'App Protection'

        $Result.PolicyTypeName | Should -Be $Expected
    }

    It 'filters Linux and device configuration script rows' -ForEach @(
        @{ Policy = [PSCustomObject]@{ id = 'linux'; displayName = 'Linux'; platforms = 'linux' } }
        @{ Policy = [PSCustomObject]@{ id = 'script'; displayName = 'Script'; templateReference = [PSCustomObject]@{ templateFamily = 'deviceConfigurationScripts' } } }
    ) {
        $Result = ConvertTo-CIPPIntunePolicyListItem -Policy $Policy -URLName 'ConfigurationPolicies' -DefaultPolicyTypeName 'Device Configuration'

        $Result | Should -BeNullOrEmpty
    }
}
