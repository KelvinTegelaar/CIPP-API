# Pester tests for Get-CIPPAppProtectionPolicyUrl.
#
# App Protection templates captured through a concrete Graph collection carry no @odata.type -
# Graph only emits it for reads through the polymorphic managedAppPolicies collection - so
# deployment used to reject them outright. These cover the order the type is resolved in.

BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
    . (Join-Path $RepoRoot 'Modules/CIPPCore/Public/Get-CIPPAppProtectionPolicyUrl.ps1')
}

Describe 'Get-CIPPAppProtectionPolicyUrl' {

    Context 'from @odata.type' {
        It 'maps <Type> to <Expected>' -ForEach @(
            @{ Type = '#microsoft.graph.iosManagedAppProtection'; Expected = 'iosManagedAppProtections' }
            @{ Type = '#microsoft.graph.androidManagedAppProtection'; Expected = 'androidManagedAppProtections' }
            @{ Type = '#microsoft.graph.windowsManagedAppProtection'; Expected = 'windowsManagedAppProtections' }
            @{ Type = '#microsoft.graph.targetedManagedAppConfiguration'; Expected = 'targetedManagedAppConfigurations' }
            @{ Type = 'microsoft.graph.iosManagedAppProtection'; Expected = 'iosManagedAppProtections' }
            @{ Type = 'iosManagedAppProtection'; Expected = 'iosManagedAppProtections' }
        ) {
            Get-CIPPAppProtectionPolicyUrl -Policy ([PSCustomObject]@{ '@odata.type' = $Type }) |
                Should -Be $Expected
        }

        It 'pluralises <Type> correctly rather than appending an s' -ForEach @(
            @{ Type = '#microsoft.graph.windowsInformationProtectionPolicy'; Expected = 'windowsInformationProtectionPolicies' }
            @{ Type = '#microsoft.graph.mdmWindowsInformationProtectionPolicy'; Expected = 'mdmWindowsInformationProtectionPolicies' }
        ) {
            Get-CIPPAppProtectionPolicyUrl -Policy ([PSCustomObject]@{ '@odata.type' = $Type }) |
                Should -Be $Expected
        }
    }

    Context 'from @odata.context' {
        It 'reads the collection out of the context of a concrete-type read' {
            # This is the shape every template captured by CIPP through its own collection has.
            $Policy = [PSCustomObject]@{
                '@odata.context' = 'https://graph.microsoft.com/beta/$metadata#deviceAppManagement/iosManagedAppProtections/$entity'
                displayName      = 'App Protection - iOS'
            }

            Get-CIPPAppProtectionPolicyUrl -Policy $Policy | Should -Be 'iosManagedAppProtections'
        }

        It 'reads the type cast out of a polymorphic context' {
            $Policy = [PSCustomObject]@{
                '@odata.context' = 'https://graph.microsoft.com/beta/$metadata#deviceAppManagement/managedAppPolicies/microsoft.graph.androidManagedAppProtection/$entity'
            }

            Get-CIPPAppProtectionPolicyUrl -Policy $Policy | Should -Be 'androidManagedAppProtections'
        }

        It 'prefers @odata.type when both are present' {
            $Policy = [PSCustomObject]@{
                '@odata.type'    = '#microsoft.graph.androidManagedAppProtection'
                '@odata.context' = 'https://graph.microsoft.com/beta/$metadata#deviceAppManagement/iosManagedAppProtections/$entity'
            }

            Get-CIPPAppProtectionPolicyUrl -Policy $Policy | Should -Be 'androidManagedAppProtections'
        }

        It 'ignores a bare managedAppPolicies context, which names no platform' {
            $Policy = [PSCustomObject]@{
                '@odata.context' = 'https://graph.microsoft.com/beta/$metadata#deviceAppManagement/managedAppPolicies/$entity'
                pinRequired      = $true
            }

            Get-CIPPAppProtectionPolicyUrl -Policy $Policy | Should -BeNullOrEmpty
        }
    }

    Context 'from platform-specific settings' {
        It 'recognises an iOS policy by settings that exist nowhere else' {
            $Policy = [PSCustomObject]@{
                displayName          = 'App Protection - iOS'
                pinRequired          = $true
                faceIdBlocked        = $false
                managedUniversalLinks = @('https://*.sharepoint.com/*')
            }

            Get-CIPPAppProtectionPolicyUrl -Policy $Policy | Should -Be 'iosManagedAppProtections'
        }

        It 'recognises an Android policy by settings that exist nowhere else' {
            $Policy = [PSCustomObject]@{
                displayName         = 'App Protection - Android'
                pinRequired         = $true
                screenCaptureBlocked = $true
                encryptAppData      = $true
            }

            Get-CIPPAppProtectionPolicyUrl -Policy $Policy | Should -Be 'androidManagedAppProtections'
        }

        It 'refuses to guess when both platforms are indicated' {
            # Deploying into the wrong collection is worse than reporting an unknown type.
            $Policy = [PSCustomObject]@{
                faceIdBlocked        = $false
                screenCaptureBlocked = $true
            }

            Get-CIPPAppProtectionPolicyUrl -Policy $Policy | Should -BeNullOrEmpty
        }
    }

    Context 'input handling' {
        It 'accepts raw JSON as well as an object' {
            $RawJSON = '{"@odata.context":"https://graph.microsoft.com/beta/$metadata#deviceAppManagement/iosManagedAppProtections/$entity","displayName":"x"}'

            Get-CIPPAppProtectionPolicyUrl -Policy $RawJSON | Should -Be 'iosManagedAppProtections'
        }

        It 'returns nothing for unparseable JSON' {
            Get-CIPPAppProtectionPolicyUrl -Policy 'not json at all' | Should -BeNullOrEmpty
        }

        It 'returns nothing for a policy that identifies no platform' {
            $Policy = [PSCustomObject]@{ displayName = 'Nameless'; pinRequired = $true }

            Get-CIPPAppProtectionPolicyUrl -Policy $Policy | Should -BeNullOrEmpty
        }
    }
}
