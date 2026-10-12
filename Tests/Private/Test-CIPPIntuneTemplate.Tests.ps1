# Pester tests for Test-CIPPIntuneTemplate
# The point of this helper is that a template which cannot deploy is refused where it is introduced
# rather than reported as a successful deployment, so these cover the preconditions each type of
# payload has to satisfy and the error/warning split that decides whether a write is blocked.

BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
    $Public = Join-Path $RepoRoot 'Modules/CIPPCore/Public'

    . (Join-Path $Public 'Get-CIPPIntuneTemplateType.ps1')
    . (Join-Path $Public 'Get-CIPPIntuneDeployableType.ps1')
    . (Join-Path $Public 'Get-CIPPIntunePolicyName.ps1')
    . (Join-Path $Public 'Get-CIPPAppProtectionPolicyUrl.ps1')
    . (Join-Path $Public 'Test-CIPPIntuneCatalogPayload.ps1')
    . (Join-Path $Public 'Test-CIPPIntuneTemplate.ps1')

    # The catalog lookups are off unless asked for, so this only has to exist, not return anything.
    function Get-CIPPIntuneDefinitionIndex { return $null }

    # Tenant-aware checks. Stubbed so the static behaviour can be tested without a tenant, and
    # overridden per test where the tenant path itself is what is under test.
    function Get-CIPPTextReplacement { param($TenantFilter, $Text, [switch]$EscapeForJson) return $Text }
    function Select-CIPPIntuneAvailableSetting { param($Policy, $TenantFilter) return $Policy }

    # Convenience: the codes of every finding at a given severity.
    function Get-Code {
        param($Result, [string]$Severity)
        return @($Result.Findings | Where-Object { $_.Severity -eq $Severity } | ForEach-Object { $_.Code })
    }
}

Describe 'Test-CIPPIntuneTemplate' {

    Context 'payloads that cannot be read' {
        It 'rejects malformed JSON' {
            $Result = Test-CIPPIntuneTemplate -RawJSON '{"displayName": ' -TemplateType 'Device' -DisplayName 'Broken'
            $Result.IsValid | Should -BeFalse
            Get-Code $Result 'Error' | Should -Contain 'InvalidJson'
        }

        It 'rejects an empty payload' {
            $Result = Test-CIPPIntuneTemplate -RawJSON '' -TemplateType 'Device' -DisplayName 'Empty'
            $Result.IsValid | Should -BeFalse
            Get-Code $Result 'Error' | Should -Contain 'EmptyPayload'
        }
    }

    Context 'template type' {
        It 'rejects a type deployment does not handle, which is the case that used to report success' {
            $Result = Test-CIPPIntuneTemplate -RawJSON '{"displayName":"x"}' -TemplateType 'Intents' -DisplayName 'Legacy'
            $Result.IsValid | Should -BeFalse
            Get-Code $Result 'Error' | Should -Contain 'UndeployableType'
        }

        It 'rejects a template whose type cannot be determined at all' {
            $Result = Test-CIPPIntuneTemplate -RawJSON '{"something":"unrecognisable"}' -DisplayName 'No type'
            $Result.IsValid | Should -BeFalse
            Get-Code $Result 'Error' | Should -Contain 'UnknownType'
        }

        It 'accepts an inferred type but says it was inferred' {
            $RawJSON = '{"@odata.type":"#microsoft.graph.windows10GeneralConfiguration","displayName":"x"}'
            $Result = Test-CIPPIntuneTemplate -RawJSON $RawJSON -DisplayName 'Inferred'
            $Result.IsValid | Should -BeTrue
            $Result.Type | Should -Be 'Device'
            Get-Code $Result 'Warning' | Should -Contain 'InferredType'
        }

        It 'accepts every type deployment supports' -ForEach @(
            @{ Type = 'windowsDriverUpdateProfiles' }
            @{ Type = 'windowsFeatureUpdateProfiles' }
            @{ Type = 'windowsQualityUpdatePolicies' }
            @{ Type = 'windowsQualityUpdateProfiles' }
        ) {
            $Result = Test-CIPPIntuneTemplate -RawJSON '{"displayName":"Update ring"}' -TemplateType $Type -DisplayName 'Update ring'
            $Result.IsValid | Should -BeTrue
        }
    }

    Context 'policy name' {
        It 'rejects a template that would deploy an unnamed policy' {
            $Result = Test-CIPPIntuneTemplate -RawJSON '{"@odata.type":"#microsoft.graph.windows10GeneralConfiguration"}' -TemplateType 'Device' -DisplayName ''
            $Result.IsValid | Should -BeFalse
            Get-Code $Result 'Error' | Should -Contain 'NoDisplayName'
        }

        It 'reports the name the policy would actually deploy under, not the column' {
            # Catalog takes its name from the payload and ignores the Displayname column.
            $Result = Test-CIPPIntuneTemplate -RawJSON '{"name":"From payload","settings":[],"technologies":"mdm"}' -TemplateType 'Catalog' -DisplayName 'From column'
            $Result.DisplayName | Should -Be 'From payload'
        }
    }

    Context 'Device' {
        It 'requires @odata.type, because Graph cannot pick the concrete configuration type without it' {
            $Result = Test-CIPPIntuneTemplate -RawJSON '{"displayName":"No type"}' -TemplateType 'Device' -DisplayName 'No type'
            $Result.IsValid | Should -BeFalse
            Get-Code $Result 'Error' | Should -Contain 'MissingODataType'
        }

        It 'accepts a device configuration carrying @odata.type' {
            $RawJSON = '{"@odata.type":"#microsoft.graph.windows10GeneralConfiguration","displayName":"Baseline"}'
            $Result = Test-CIPPIntuneTemplate -RawJSON $RawJSON -TemplateType 'Device' -DisplayName 'Baseline'
            $Result.IsValid | Should -BeTrue
            $Result.Errors | Should -BeNullOrEmpty
        }
    }

    Context 'deviceCompliancePolicies' {
        It 'requires scheduledActionsForRule, which deployment assigns into directly' {
            $RawJSON = '{"@odata.type":"#microsoft.graph.windows10CompliancePolicy","displayName":"Compliance"}'
            $Result = Test-CIPPIntuneTemplate -RawJSON $RawJSON -TemplateType 'deviceCompliancePolicies' -DisplayName 'Compliance'
            $Result.IsValid | Should -BeFalse
            Get-Code $Result 'Error' | Should -Contain 'MissingScheduledActions'
        }

        It 'accepts a compliance policy that carries it' {
            $RawJSON = '{"@odata.type":"#microsoft.graph.windows10CompliancePolicy","displayName":"Compliance","scheduledActionsForRule":[]}'
            $Result = Test-CIPPIntuneTemplate -RawJSON $RawJSON -TemplateType 'deviceCompliancePolicies' -DisplayName 'Compliance'
            $Result.IsValid | Should -BeTrue
        }

        It 'warns rather than fails when @odata.type is absent, since only matching suffers' {
            $RawJSON = '{"displayName":"Compliance","scheduledActionsForRule":[]}'
            $Result = Test-CIPPIntuneTemplate -RawJSON $RawJSON -TemplateType 'deviceCompliancePolicies' -DisplayName 'Compliance'
            $Result.IsValid | Should -BeTrue
            Get-Code $Result 'Warning' | Should -Contain 'MissingODataType'
        }
    }

    Context 'Admin' {
        It 'requires an added array, because that is what updateDefinitionValues applies' {
            $Result = Test-CIPPIntuneTemplate -RawJSON '{"deletedIds":[]}' -TemplateType 'Admin' -DisplayName 'ADMX'
            $Result.IsValid | Should -BeFalse
            Get-Code $Result 'Error' | Should -Contain 'MissingDefinitionValues'
        }

        It 'warns that an empty added array would configure nothing' {
            $Result = Test-CIPPIntuneTemplate -RawJSON '{"added":[],"deletedIds":[]}' -TemplateType 'Admin' -DisplayName 'ADMX'
            $Result.IsValid | Should -BeTrue
            Get-Code $Result 'Warning' | Should -Contain 'EmptyDefinitionValues'
        }
    }

    Context 'AppProtection' {
        It 'rejects a policy that identifies no platform, so there is no collection to post to' {
            $Result = Test-CIPPIntuneTemplate -RawJSON '{"displayName":"MAM"}' -TemplateType 'AppProtection' -DisplayName 'MAM'
            $Result.IsValid | Should -BeFalse
            Get-Code $Result 'Error' | Should -Contain 'AppProtectionPlatformUnknown'
        }

        It 'accepts one whose platform is resolvable from @odata.type' {
            $RawJSON = '{"@odata.type":"#microsoft.graph.iosManagedAppProtection","displayName":"MAM"}'
            $Result = Test-CIPPIntuneTemplate -RawJSON $RawJSON -TemplateType 'AppProtection' -DisplayName 'MAM'
            $Result.IsValid | Should -BeTrue
        }
    }

    Context 'Catalog' {
        It 'requires a settings array' {
            $Result = Test-CIPPIntuneTemplate -RawJSON '{"name":"Catalog","technologies":"mdm"}' -TemplateType 'Catalog' -DisplayName 'Catalog'
            $Result.IsValid | Should -BeFalse
            Get-Code $Result 'Error' | Should -Contain 'MissingSettings'
        }

        It 'rejects a setting instance missing @odata.type' {
            $RawJSON = @'
{"name":"Catalog","technologies":"mdm","settings":[
  {"settingInstance":{"settingDefinitionId":"device_test","choiceSettingValue":{"value":"device_test_1","children":[]}}}
]}
'@
            $Result = Test-CIPPIntuneTemplate -RawJSON $RawJSON -TemplateType 'Catalog' -DisplayName 'Catalog'
            $Result.IsValid | Should -BeFalse
            Get-Code $Result 'Error' | Should -Contain 'MissingSettingODataType'
        }

        It 'rejects a setting instance missing settingDefinitionId' {
            $RawJSON = @'
{"name":"Catalog","technologies":"mdm","settings":[
  {"settingInstance":{"@odata.type":"#microsoft.graph.deviceManagementConfigurationChoiceSettingInstance","choiceSettingValue":{"value":"x","children":[]}}}
]}
'@
            $Result = Test-CIPPIntuneTemplate -RawJSON $RawJSON -TemplateType 'Catalog' -DisplayName 'Catalog'
            $Result.IsValid | Should -BeFalse
            Get-Code $Result 'Error' | Should -Contain 'MissingSettingDefinitionId'
        }

        It 'finds a problem nested inside a choice value, not just at the top level' {
            $RawJSON = @'
{"name":"Catalog","technologies":"mdm","settings":[
  {"settingInstance":{
    "@odata.type":"#microsoft.graph.deviceManagementConfigurationChoiceSettingInstance",
    "settingDefinitionId":"device_parent",
    "choiceSettingValue":{"value":"device_parent_1","children":[
      {"settingDefinitionId":"device_child","simpleSettingValue":{"@odata.type":"#microsoft.graph.deviceManagementConfigurationStringSettingValue","value":"v"}}
    ]}}}
]}
'@
            $Result = Test-CIPPIntuneTemplate -RawJSON $RawJSON -TemplateType 'Catalog' -DisplayName 'Catalog'
            $Result.IsValid | Should -BeFalse
            $Nested = $Result.Findings | Where-Object { $_.Code -eq 'MissingSettingODataType' }
            $Nested.Path | Should -Match 'children\[0\]'
        }

        It 'reports a simple setting value with no value type' {
            $RawJSON = @'
{"name":"Catalog","technologies":"mdm","settings":[
  {"settingInstance":{
    "@odata.type":"#microsoft.graph.deviceManagementConfigurationSimpleSettingInstance",
    "settingDefinitionId":"device_test",
    "simpleSettingValue":{"value":"no type"}}}
]}
'@
            $Result = Test-CIPPIntuneTemplate -RawJSON $RawJSON -TemplateType 'Catalog' -DisplayName 'Catalog'
            $Result.IsValid | Should -BeFalse
            Get-Code $Result 'Error' | Should -Contain 'MissingValueODataType'
        }

        It 'accepts a well-formed settings catalog policy' {
            $RawJSON = @'
{"name":"Catalog","technologies":"mdm","settings":[
  {"settingInstance":{
    "@odata.type":"#microsoft.graph.deviceManagementConfigurationChoiceSettingInstance",
    "settingDefinitionId":"device_test",
    "choiceSettingValue":{"value":"device_test_1","children":[]}}}
]}
'@
            $Result = Test-CIPPIntuneTemplate -RawJSON $RawJSON -TemplateType 'Catalog' -DisplayName 'Catalog'
            $Result.IsValid | Should -BeTrue
            $Result.Errors | Should -BeNullOrEmpty
        }

        It 'warns about an empty settings array rather than failing it' {
            $Result = Test-CIPPIntuneTemplate -RawJSON '{"name":"Catalog","technologies":"mdm","settings":[]}' -TemplateType 'Catalog' -DisplayName 'Catalog'
            $Result.IsValid | Should -BeTrue
            Get-Code $Result 'Warning' | Should -Contain 'EmptySettings'
        }
    }

    Context 'Catalog checks against the definition index' {
        BeforeAll {
            $Options = [System.Collections.Generic.Dictionary[string, string]]::new([System.StringComparer]::OrdinalIgnoreCase)
            $Options['asr_rule_block'] = 'Block'
            $script:Index = [System.Collections.Generic.Dictionary[string, object]]::new([System.StringComparer]::OrdinalIgnoreCase)
            $script:Index['asr_rules'] = @{ displayName = 'ASR Rules'; options = $null; minimumCount = 0; maximumCount = [int64]1 }
            $script:Index['asr_rule'] = @{ displayName = 'ASR Rule'; options = $Options; minimumCount = $null; maximumCount = $null }
            function Get-CIPPIntuneDefinitionIndex { return $script:Index }

            $script:Catalog = {
                param([int]$Rows, [string]$Value)
                $Entry = '{"children":[{"@odata.type":"#microsoft.graph.deviceManagementConfigurationChoiceSettingInstance","settingDefinitionId":"asr_rule","choiceSettingValue":{"value":"' + $Value + '","children":[]}}]}'
                '{"name":"ASR","technologies":"mdm","settings":[{"settingInstance":{"@odata.type":"#microsoft.graph.deviceManagementConfigurationGroupSettingCollectionInstance","settingDefinitionId":"asr_rules","groupSettingCollectionValue":[' + ((1..$Rows | ForEach-Object { $Entry }) -join ',') + ']}}]}'
            }
        }

        It 'refuses a collection with more rows than Intune allows' {
            $Result = Test-CIPPIntuneTemplate -RawJSON (& $script:Catalog 2 'asr_rule_block') -TemplateType 'Catalog' -DisplayName 'ASR' -IncludeCatalogChecks
            Get-Code $Result 'Error' | Should -Contain 'TooManyCollectionEntries'
        }

        It 'warns, without failing, about a choice the catalog does not list' {
            $Result = Test-CIPPIntuneTemplate -RawJSON (& $script:Catalog 1 'asr_rule_unknown') -TemplateType 'Catalog' -DisplayName 'ASR' -IncludeCatalogChecks
            $Result.IsValid | Should -BeTrue
            Get-Code $Result 'Warning' | Should -Contain 'UnknownChoiceValue'
        }

        It 'skips catalog lookups unless asked' {
            $Result = Test-CIPPIntuneTemplate -RawJSON (& $script:Catalog 2 'asr_rule_unknown') -TemplateType 'Catalog' -DisplayName 'ASR'
            $Result.Findings | Should -BeNullOrEmpty
        }
    }

    Context 'accepting an already parsed payload' {
        It 'validates an object the same way it validates its JSON' {
            $Policy = [pscustomobject]@{ '@odata.type' = '#microsoft.graph.windows10GeneralConfiguration'; displayName = 'Parsed' }
            $Result = Test-CIPPIntuneTemplate -RawJSON $Policy -DisplayName 'Parsed'
            $Result.IsValid | Should -BeTrue
            $Result.Type | Should -Be 'Device'
        }
    }

    Context 'tenant-aware checks' {
        It 'does not run them without a tenant' {
            $RawJSON = '{"@odata.type":"#microsoft.graph.windows10GeneralConfiguration","displayName":"%tenantname% baseline"}'
            $Result = Test-CIPPIntuneTemplate -RawJSON $RawJSON -TemplateType 'Device' -DisplayName 'Baseline'
            Get-Code $Result 'Warning' | Should -Not -Contain 'UnresolvedVariable'
        }

        It 'warns about a variable the tenant does not resolve' {
            # Stands in for a replacement pass that resolved everything it knew and left one behind.
            function Get-CIPPTextReplacement { param($TenantFilter, $Text, [switch]$EscapeForJson) return $Text }

            $RawJSON = '{"@odata.type":"#microsoft.graph.windows10GeneralConfiguration","displayName":"%customvar% baseline"}'
            $Result = Test-CIPPIntuneTemplate -RawJSON $RawJSON -TemplateType 'Device' -DisplayName 'Baseline' -TenantFilter 'contoso.onmicrosoft.com'

            Get-Code $Result 'Warning' | Should -Contain 'UnresolvedVariable'
            # A warning, so it never blocks a save.
            $Result.IsValid | Should -BeTrue
        }

        It 'ignores Windows environment variables, which are not CIPP tokens' {
            # Intune policies are full of paths like %programfiles%. Those are meant to reach the
            # device unexpanded, so reporting them would put a warning on correct templates.
            function Get-CIPPTextReplacement { param($TenantFilter, $Text, [switch]$EscapeForJson) return $Text }

            $RawJSON = '{"@odata.type":"#microsoft.graph.windows10GeneralConfiguration","displayName":"x","path":"%ProgramFiles%\\App;%WINDIR%\\System32;%LocalAppData%"}'
            $Result = Test-CIPPIntuneTemplate -RawJSON $RawJSON -TemplateType 'Device' -DisplayName 'Baseline' -TenantFilter 'contoso.onmicrosoft.com'

            Get-Code $Result 'Warning' | Should -Not -Contain 'UnresolvedVariable'
        }

        It 'still reports a genuine unresolved token alongside environment variables' {
            function Get-CIPPTextReplacement { param($TenantFilter, $Text, [switch]$EscapeForJson) return $Text }

            $RawJSON = '{"@odata.type":"#microsoft.graph.windows10GeneralConfiguration","displayName":"%custvar% x","path":"%ProgramFiles%"}'
            $Result = Test-CIPPIntuneTemplate -RawJSON $RawJSON -TemplateType 'Device' -DisplayName 'Baseline' -TenantFilter 'contoso.onmicrosoft.com'

            $Warning = @($Result.Findings | Where-Object { $_.Code -eq 'UnresolvedVariable' })
            $Warning | Should -Not -BeNullOrEmpty
            $Warning.Message | Should -Match '%custvar%'
            $Warning.Message | Should -Not -Match 'ProgramFiles'
        }

        It 'fails a Catalog template the tenant offers none of the settings for' {
            function Select-CIPPIntuneAvailableSetting {
                param($Policy, $TenantFilter)
                $Policy.settings = @()
                return $Policy
            }

            $RawJSON = @'
{"name":"ES","technologies":"mdm","templateReference":{"templateId":"abc"},"settings":[
  {"settingInstance":{
    "@odata.type":"#microsoft.graph.deviceManagementConfigurationChoiceSettingInstance",
    "settingDefinitionId":"device_test",
    "choiceSettingValue":{"value":"device_test_1","children":[]}}}
]}
'@
            $Result = Test-CIPPIntuneTemplate -RawJSON $RawJSON -TemplateType 'Catalog' -DisplayName 'ES' -TenantFilter 'contoso.onmicrosoft.com'
            $Result.IsValid | Should -BeFalse
            Get-Code $Result 'Error' | Should -Contain 'NoSettingsAvailable'
        }
    }
}
