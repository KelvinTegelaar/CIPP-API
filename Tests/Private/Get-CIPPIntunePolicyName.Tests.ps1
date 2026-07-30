# Pester tests for Get-CIPPIntunePolicyName
# Covers the split between types named from the Displayname column and types named from their
# payload, which is what decides whether a deployed policy can be found again.

BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
    . (Join-Path $RepoRoot 'Modules/CIPPCore/Public/Get-CIPPIntunePolicyName.ps1')
}

Describe 'Get-CIPPIntunePolicyName' {

    Context 'types named from the Displayname column' {
        It 'returns the Displayname for <Type> even when the payload says otherwise' -ForEach @(
            @{ Type = 'Device' }
            @{ Type = 'deviceCompliancePolicies' }
            @{ Type = 'AppProtection' }
            @{ Type = 'AppConfiguration' }
            @{ Type = 'Admin' }
        ) {
            $RawJSON = '{"displayName":"Name from payload","name":"Other name"}'
            Get-CIPPIntunePolicyName -TemplateType $Type -RawJSON $RawJSON -DisplayName 'Name from column' |
                Should -Be 'Name from column'
        }
    }

    Context 'Catalog' {
        It 'uses the payload name, because that is what deployment sends' {
            $RawJSON = '{"name":"Baseline - Defender","description":"x"}'
            Get-CIPPIntunePolicyName -TemplateType 'Catalog' -RawJSON $RawJSON -DisplayName 'Renamed in CIPP' |
                Should -Be 'Baseline - Defender'
        }

        It 'ignores displayName on a Catalog payload' {
            $RawJSON = '{"name":"Correct","displayName":"Wrong"}'
            Get-CIPPIntunePolicyName -TemplateType 'Catalog' -RawJSON $RawJSON -DisplayName 'Column' |
                Should -Be 'Correct'
        }

        It 'falls back to the column when the payload has no name' {
            Get-CIPPIntunePolicyName -TemplateType 'Catalog' -RawJSON '{"description":"x"}' -DisplayName 'Column' |
                Should -Be 'Column'
        }

        It 'resolves the replaced name when text replacement has already run' {
            # Deployment replaces tenant variables before reading the name, so a lookup on the
            # unreplaced payload would search for a policy that never existed.
            $RawJSON = '{"name":"Contoso - Outlook configuration"}'
            Get-CIPPIntunePolicyName -TemplateType 'Catalog' -RawJSON $RawJSON -DisplayName '%tenantname% - Outlook configuration' |
                Should -Be 'Contoso - Outlook configuration'
        }
    }

    Context 'Windows update profile types' {
        It 'uses the payload displayName for <Type>' -ForEach @(
            @{ Type = 'windowsDriverUpdateProfiles' }
            @{ Type = 'windowsFeatureUpdateProfiles' }
            @{ Type = 'windowsQualityUpdatePolicies' }
            @{ Type = 'windowsQualityUpdateProfiles' }
        ) {
            $RawJSON = '{"displayName":"Payload name"}'
            Get-CIPPIntunePolicyName -TemplateType $Type -RawJSON $RawJSON -DisplayName 'Column name' |
                Should -Be 'Payload name'
        }

        It 'falls back to the payload name property when displayName is absent' {
            Get-CIPPIntunePolicyName -TemplateType 'windowsDriverUpdateProfiles' -RawJSON '{"name":"From name"}' -DisplayName 'Column' |
                Should -Be 'From name'
        }
    }

    Context 'input handling' {
        It 'accepts an already parsed payload' {
            $Policy = [PSCustomObject]@{ name = 'Parsed policy' }
            Get-CIPPIntunePolicyName -TemplateType 'Catalog' -RawJSON $Policy -DisplayName 'Column' |
                Should -Be 'Parsed policy'
        }

        It 'falls back to the column when the payload cannot be parsed' {
            # Returning nothing here would make every lookup miss and report the policy as absent.
            Get-CIPPIntunePolicyName -TemplateType 'Catalog' -RawJSON 'not json' -DisplayName 'Column' -WarningAction SilentlyContinue |
                Should -Be 'Column'
        }

        It 'falls back to the column when the payload name is whitespace' {
            Get-CIPPIntunePolicyName -TemplateType 'Catalog' -RawJSON '{"name":"   "}' -DisplayName 'Column' |
                Should -Be 'Column'
        }
    }
}
