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
}
