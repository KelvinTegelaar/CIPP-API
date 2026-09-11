# Pester tests for Select-CIPPIntuneAvailableSetting.
#
# The helper reduces a Catalog policy to the settings a tenant offers. ThrowOnMissingRequired adds a
# deploy-only guard for Apple enrollment (ADE) policies: Microsoft marks every Setup Assistant option
# required and keeps adding new ones, so a template captured before an option existed can no longer
# deploy and Graph returns an opaque "required Setting not present" error. The guard must fire only
# for the enrollment family, only when asked, and only when a required setting is genuinely absent.

BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))

    # Stub mirrors the real signature so drift fails loudly here.
    function New-GraphGETRequest { [CmdletBinding()] param($uri, $tenantid, $AsApp, $ComplexFilter) }

    . (Join-Path $RepoRoot 'Modules/CIPPCore/Public/Select-CIPPIntuneAvailableSetting.ps1')

    $script:Tenant = 'contoso.onmicrosoft.com'

    # Builds one settingTemplates entry as Graph returns it (settingInstanceTemplate + expanded
    # settingDefinitions), matching what the helper reads.
    function New-SettingTemplate {
        param($InstanceId, $DefinitionId, [bool]$Required, $DisplayName)
        [PSCustomObject]@{
            settingInstanceTemplate = [PSCustomObject]@{
                settingInstanceTemplateId  = $InstanceId
                settingDefinitionId        = $DefinitionId
                isRequired                 = $Required
                choiceSettingValueTemplate = [PSCustomObject]@{ settingValueTemplateId = "$InstanceId-val" }
            }
            settingDefinitions      = @([PSCustomObject]@{ id = $DefinitionId; displayName = $DisplayName })
        }
    }

    # Builds one policy setting instance referencing a setting instance template.
    function New-PolicySetting {
        param($InstanceId, $DefinitionId)
        [PSCustomObject]@{
            settingInstance = [PSCustomObject]@{
                settingDefinitionId              = $DefinitionId
                settingInstanceTemplateReference = [PSCustomObject]@{ settingInstanceTemplateId = $InstanceId }
                choiceSettingValue               = [PSCustomObject]@{
                    value                         = "$DefinitionId`_1"
                    settingValueTemplateReference = [PSCustomObject]@{ settingValueTemplateId = "$InstanceId-val" }
                }
            }
        }
    }

    # An ADE-style template: two required settings, one optional.
    $script:AdeSettingTemplates = @(
        New-SettingTemplate -InstanceId 'inst-affinity' -DefinitionId 'ade_useraffinity' -Required $true -DisplayName 'User affinity'
        New-SettingTemplate -InstanceId 'inst-a11y' -DefinitionId 'ade_setupassistant_accessibilityappearance' -Required $true -DisplayName 'Accessibility appearance'
        New-SettingTemplate -InstanceId 'inst-certs' -DefinitionId 'ade_appleconfiguratorcertificates' -Required $false -DisplayName 'Certificates'
    )

    function New-AdePolicy {
        param([string[]]$IncludeInstanceIds)
        $map = @{
            'inst-affinity' = 'ade_useraffinity'
            'inst-a11y'     = 'ade_setupassistant_accessibilityappearance'
            'inst-certs'    = 'ade_appleconfiguratorcertificates'
        }
        $settings = @(foreach ($id in $IncludeInstanceIds) { New-PolicySetting -InstanceId $id -DefinitionId $map[$id] })
        [PSCustomObject]@{
            name              = 'iOS Enrollment'
            technologies      = 'enrollment'
            templateReference = [PSCustomObject]@{ templateId = 'ade-template_1'; templateFamily = 'enrollmentConfiguration' }
            settings          = $settings
        }
    }
}

Describe 'Select-CIPPIntuneAvailableSetting -ThrowOnMissingRequired' {
    BeforeEach {
        # Isolate the per-tenant/template lookup cache between tests.
        $script:CIPPIntuneSettingTemplateCache = @{}
        Mock -CommandName New-GraphGETRequest -MockWith { $script:AdeSettingTemplates }
    }

    Context 'an Apple enrollment policy missing a required setting' {
        It 'throws an actionable error naming the missing setting by its friendly name' {
            $Policy = New-AdePolicy -IncludeInstanceIds @('inst-affinity', 'inst-certs')

            { Select-CIPPIntuneAvailableSetting -Policy $Policy -TenantFilter $script:Tenant -ThrowOnMissingRequired } |
                Should -Throw -ExpectedMessage '*Accessibility appearance*'
        }

        It 'does not throw when the guard is not requested (comparison and drift paths)' {
            $Policy = New-AdePolicy -IncludeInstanceIds @('inst-affinity', 'inst-certs')

            { Select-CIPPIntuneAvailableSetting -Policy $Policy -TenantFilter $script:Tenant } |
                Should -Not -Throw
        }
    }

    Context 'an Apple enrollment policy with every required setting present' {
        It 'returns the policy without throwing' {
            $Policy = New-AdePolicy -IncludeInstanceIds @('inst-affinity', 'inst-a11y', 'inst-certs')

            $Result = Select-CIPPIntuneAvailableSetting -Policy $Policy -TenantFilter $script:Tenant -ThrowOnMissingRequired
            $Result.name | Should -Be 'iOS Enrollment'
        }
    }

    Context 'a non-enrollment (Endpoint Security) policy missing a required setting' {
        It 'is never validated - those deploy fine as a subset' {
            $Policy = New-AdePolicy -IncludeInstanceIds @('inst-affinity', 'inst-certs')
            $Policy.technologies = 'mdm,microsoftSense'
            $Policy.templateReference.templateFamily = 'endpointSecurityAntivirus'

            { Select-CIPPIntuneAvailableSetting -Policy $Policy -TenantFilter $script:Tenant -ThrowOnMissingRequired } |
                Should -Not -Throw
        }
    }

    Context 'the setting template lookup returns nothing' {
        It 'returns the policy untouched rather than throwing' {
            Mock -CommandName New-GraphGETRequest -MockWith { @() }
            $Policy = New-AdePolicy -IncludeInstanceIds @('inst-affinity', 'inst-certs')

            { Select-CIPPIntuneAvailableSetting -Policy $Policy -TenantFilter $script:Tenant -ThrowOnMissingRequired } |
                Should -Not -Throw
        }
    }
}
