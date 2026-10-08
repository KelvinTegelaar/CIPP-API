# The V2 -> baseline migration copies a setting across verbatim when it cannot map the value,
# and the generic path only snaps a value onto a V3 option when it already equals one. A V2
# value in a different vocabulary (a switch where V3 wants 'Enabled', an enum name where V3
# wants the SPO numeric) therefore lands untranslated, and the standard reports drift on every
# run against a tenant that is actually compliant. These tests run the real migration over the
# real definitions and pin the translated variables for the standards that need a value map.

BeforeAll {
    $script:RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
    $DefinitionRoot = Join-Path $script:RepoRoot 'Config/BaselineStandards'

    function Get-CIPPBaselineDefinition { param($Name) }
    function Get-CippTable { param($tablename) }
    function Get-CIPPAzDataTableEntity { param($Filter) }
    function ConvertTo-CIPPODataFilterValue { param($Value) }
    function New-CIPPBaseline { param($Baseline, $User, $Source, $SHA) }
    function Write-LogMessage { param($API, $message, $Sev) }
    . (Join-Path $script:RepoRoot 'Modules/CIPPCore/Public/Baselines/Invoke-CIPPBaselineMigration.ps1')

    $script:Definitions = Get-ChildItem -Path $DefinitionRoot -Recurse -Filter '*.json' | ForEach-Object { Get-Content $_.FullName -Raw | ConvertFrom-Json }

    # Migrates one V2 template holding the given standards and returns the saved stage configs.
    function Invoke-Migration {
        param([hashtable]$Standards)
        $script:Saved = $null
        $Json = @{ templateName = 'Test'; tenantFilter = @(@{ label = 'Contoso'; value = 'contoso.com' }); standards = $Standards } | ConvertTo-Json -Depth 20
        Mock Get-CIPPAzDataTableEntity { @([PSCustomObject]@{ RowKey = 'v2-guid'; GUID = 'v2-guid'; JSON = $Json }) } -ParameterFilter { $Filter -like "*StandardsTemplateV2*" }
        Mock Get-CIPPAzDataTableEntity { $null } -ParameterFilter { $Filter -like "*rollout*" }
        Mock New-CIPPBaseline { $script:Saved = $Baseline; [PSCustomObject]@{ GUID = 'b-guid'; DeltaCount = 0 } }
        $Report = Invoke-CIPPBaselineMigration
        [PSCustomObject]@{ Report = $Report.templates[0]; Configs = @($script:Saved.stages[0].standards) }
    }
}

Describe 'Invoke-CIPPBaselineMigration value maps' {
    BeforeEach {
        Mock Get-CIPPBaselineDefinition { $script:Definitions }
        Mock Get-CippTable { @{} }
        Mock ConvertTo-CIPPODataFilterValue { $Value }
        Mock Write-LogMessage {}
    }

    Context 'TeamsChatProtection' {
        It 'translates the V2 switches to the Enabled/Disabled strings the Teams cmdlet takes' {
            $Result = Invoke-Migration @{ TeamsChatProtection = @{ action = @('warn'); standards = @{ TeamsChatProtection = @{ FileTypeCheck = $true; UrlReputationCheck = $false } } } }
            $Config = $Result.Configs | Where-Object standard -EQ 'TeamsChatProtection'
            $Config.variables.FileTypeCheck | Should -BeExactly 'Enabled'
            $Config.variables.UrlReputationCheck | Should -BeExactly 'Disabled'
        }
    }

    Context 'DefaultSharingLink' {
        It 'translates the V2 enum names to the SPO numerics the definition compares against' {
            $Internal = Invoke-Migration @{ DefaultSharingLink = @{ action = @('warn'); standards = @{ DefaultSharingLink = @{ SharingLinkType = @{ label = 'Internal - Only people in your organization'; value = 'Internal' } } } } }
            $Direct = Invoke-Migration @{ DefaultSharingLink = @{ action = @('warn'); standards = @{ DefaultSharingLink = @{ SharingLinkType = 'Direct' } } } }
            ($Internal.Configs | Where-Object standard -EQ 'DefaultSharingLink').variables.sharingLinkType | Should -Be 2
            ($Direct.Configs | Where-Object standard -EQ 'DefaultSharingLink').variables.sharingLinkType | Should -Be 1
        }

        It 'lands on the definition option value so the editor shows the selection' {
            $Result = Invoke-Migration @{ DefaultSharingLink = @{ action = @('warn'); standards = @{ DefaultSharingLink = @{ SharingLinkType = 'Internal' } } } }
            $Value = ($Result.Configs | Where-Object standard -EQ 'DefaultSharingLink').variables.sharingLinkType
            $Options = ($script:Definitions | Where-Object name -EQ 'DefaultSharingLink').variables.sharingLinkType.options.value
            $Options | Should -Contain $Value
        }
    }

    Context 'Template picker multi-selects' {
        It 'fans a V2 GroupTemplate multi-select out to one instance per template' {
            $Result = Invoke-Migration @{ GroupTemplate = @(@{ action = @('Report'); groupTemplate = @(@{ label = 'Sales'; value = 'g-1' }, @{ label = 'HR'; value = 'g-2' }) }) }
            $Configs = @($Result.Configs | Where-Object standard -EQ 'GroupTemplate')
            $Configs.Count | Should -Be 2
            @($Configs.variables.groupTemplate) | Should -Be @('g-1', 'g-2')
            @($Configs.instance | Select-Object -Unique).Count | Should -Be 2
        }

        It 'unwraps a single-item V2 selection to the plain template id' {
            $Result = Invoke-Migration @{ GroupTemplate = @(@{ action = @('Report'); groupTemplate = @(@{ label = 'Sales'; value = 'g-1' }) }) }
            $Config = $Result.Configs | Where-Object standard -EQ 'GroupTemplate'
            $Config.variables.groupTemplate | Should -BeExactly 'g-1'
        }

        It 'keys the instance the same way as a single-value selection so re-migration updates in place' {
            $Multi = Invoke-Migration @{ GroupTemplate = @(@{ action = @('Report'); groupTemplate = @(@{ label = 'Sales'; value = 'g-1' }) }) }
            $Single = Invoke-Migration @{ GroupTemplate = @(@{ action = @('Report'); groupTemplate = @{ label = 'Sales'; value = 'g-1' } }) }
            ($Multi.Configs | Where-Object standard -EQ 'GroupTemplate').instance | Should -Be ($Single.Configs | Where-Object standard -EQ 'GroupTemplate').instance
        }

        It 'carries the remaining settings onto every fanned-out instance' {
            $Result = Invoke-Migration @{ TransportRuleTemplate = @(@{ action = @('Report'); transportRuleTemplate = @(@{ label = 'A'; value = 't-1' }, @{ label = 'B'; value = 't-2' }); overwrite = $true }) }
            $Configs = @($Result.Configs | Where-Object standard -EQ 'TransportRuleTemplate')
            $Configs.Count | Should -Be 2
            $Configs | ForEach-Object { $_.variables.overwrite | Should -BeTrue }
        }

        It 'maps the generic V2 picker keys onto the V3 identity variable' {
            $Reusable = Invoke-Migration @{ ReusableSettingsTemplate = @(@{ action = @('Report'); TemplateList = @(@{ label = 'A'; value = 'r-1' }, @{ label = 'B'; value = 'r-2' }) }) }
            $SafeLinks = Invoke-Migration @{ SafeLinksTemplatePolicy = @{ action = @('Report'); standards = @{ SafeLinksTemplatePolicy = @{ TemplateIds = @(@{ label = 'A'; value = 's-1' }) } } } }
            @(($Reusable.Configs | Where-Object standard -EQ 'ReusableSettingsTemplate').variables.reusableSettingsTemplate) | Should -Be @('r-1', 'r-2')
            ($SafeLinks.Configs | Where-Object standard -EQ 'SafeLinksTemplatePolicy').variables.safeLinksTemplate | Should -BeExactly 's-1'
            @($Reusable.Report.warnings) + @($SafeLinks.Report.warnings) | Where-Object { $_ -match 'does not map' } | Should -BeNullOrEmpty
        }
    }

    Context 'AppDeploy' {
        It 'fans a V2 template-mode multi-select out to one instance per App Approval template' {
            $Result = Invoke-Migration @{ AppDeploy = @{ action = @('warn'); standards = @{ AppDeploy = @{ mode = @{ label = 'Template'; value = 'template' }; templateIds = @(@{ label = 'App A'; value = 'tpl-a' }, @{ label = 'App B'; value = 'tpl-b' }) } } } }
            $Configs = @($Result.Configs | Where-Object standard -EQ 'AppDeploy')
            $Configs.Count | Should -Be 2
            @($Configs.variables.templateIds) | Should -Be @('tpl-a', 'tpl-b')
            @($Configs.instance | Select-Object -Unique).Count | Should -Be 2
            $Configs | ForEach-Object { $_.variables.mode | Should -BeExactly 'template' }
        }

        It 'keeps a V2 copy-permissions entry as one instance with its app ids' {
            $Result = Invoke-Migration @{ AppDeploy = @{ action = @('warn'); standards = @{ AppDeploy = @{ mode = 'copy'; appids = 'id-1, id-2' } } } }
            $Configs = @($Result.Configs | Where-Object standard -EQ 'AppDeploy')
            $Configs.Count | Should -Be 1
            $Configs[0].variables.appids | Should -BeExactly 'id-1, id-2'
            $Configs[0].instance | Should -Match '^AppDeploy#m[0-9a-f]{8}$'
        }
    }
}
