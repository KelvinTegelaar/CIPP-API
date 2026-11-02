# Pester tests for Merge-CIPPIntuneTemplateIdentity
# Guards the case that makes a template permanently non-compliant: remediation writes the
# template's Displayname/Description columns onto the policy, so the baseline has to carry those
# same values or the comparison reports a difference remediation has already resolved.

BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
    . (Join-Path $RepoRoot 'Modules/CIPPCore/Public/Merge-CIPPIntuneTemplateIdentity.ps1')
}

Describe 'Merge-CIPPIntuneTemplateIdentity' {

    Context 'types deployment writes the columns onto' {
        It 'overwrites a stale payload description for <Type>' -ForEach @(
            @{ Type = 'Device' }
            @{ Type = 'deviceCompliancePolicies' }
            @{ Type = 'AppProtection' }
            @{ Type = 'AppConfiguration' }
        ) {
            $Policy = [PSCustomObject]@{
                displayName = 'Old name'
                description = 'Compliance Policy for Defender for Endpoint'
            }

            $Result = Merge-CIPPIntuneTemplateIdentity -Policy $Policy -TemplateType $Type -DisplayName 'New name' -Description 'Edited in CIPP'

            $Result.displayName | Should -Be 'New name'
            $Result.description | Should -Be 'Edited in CIPP'
        }

        It 'adds the identity fields when the payload has none' {
            $Policy = [PSCustomObject]@{ someSetting = $true }

            $Result = Merge-CIPPIntuneTemplateIdentity -Policy $Policy -TemplateType 'Device' -DisplayName 'Name' -Description 'Desc'

            $Result.displayName | Should -Be 'Name'
            $Result.description | Should -Be 'Desc'
            $Result.someSetting | Should -BeTrue
        }

        It 'clears the description when the column is empty, mirroring deployment' {
            $Policy = [PSCustomObject]@{ displayName = 'Name'; description = 'Left over' }

            $Result = Merge-CIPPIntuneTemplateIdentity -Policy $Policy -TemplateType 'Device' -DisplayName 'Name' -Description ''

            $Result.description | Should -BeNullOrEmpty
        }

        It 'leaves the payload name alone when the column is empty' {
            $Policy = [PSCustomObject]@{ displayName = 'Payload name' }

            $Result = Merge-CIPPIntuneTemplateIdentity -Policy $Policy -TemplateType 'Device' -DisplayName '' -Description 'Desc'

            $Result.displayName | Should -Be 'Payload name'
        }
    }

    Context 'types deployment sends as-is' {
        It 'does not touch <Type>, which is named and described by its payload' -ForEach @(
            @{ Type = 'Catalog' }
            @{ Type = 'windowsDriverUpdateProfiles' }
            @{ Type = 'windowsFeatureUpdateProfiles' }
            @{ Type = 'windowsQualityUpdatePolicies' }
            @{ Type = 'windowsQualityUpdateProfiles' }
        ) {
            $Policy = [PSCustomObject]@{ name = 'Payload name'; description = 'Payload description' }

            $Result = Merge-CIPPIntuneTemplateIdentity -Policy $Policy -TemplateType $Type -DisplayName 'Column' -Description 'Column description'

            $Result.name | Should -Be 'Payload name'
            $Result.description | Should -Be 'Payload description'
        }

        It 'leaves Admin alone, whose payload holds definition values rather than a policy' {
            $Policy = [PSCustomObject]@{ added = @(); updated = @(); deletedIds = @() }

            $Result = Merge-CIPPIntuneTemplateIdentity -Policy $Policy -TemplateType 'Admin' -DisplayName 'Column' -Description 'Column description'

            $Result.PSObject.Properties.Name | Should -Not -Contain 'displayName'
            $Result.PSObject.Properties.Name | Should -Not -Contain 'description'
        }
    }

    Context 'input handling' {
        It 'returns null unchanged' {
            Merge-CIPPIntuneTemplateIdentity -Policy $null -TemplateType 'Device' -DisplayName 'Name' -Description 'Desc' |
                Should -BeNullOrEmpty
        }
    }
}
