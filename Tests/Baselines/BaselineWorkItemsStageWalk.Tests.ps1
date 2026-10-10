# Stage supersession by SEMANTIC identity (issue #789). The editor mints a fresh instance
# key on every add, so the same CA/Intune/Autopilot template re-added in a later stage
# arrives under a different instance key - the ascending stage walk must still let the
# later stage's config replace the earlier one (stages are additive, later wins) instead
# of parking both at Conflict. A genuine duplicate INSIDE one stage must still conflict.

BeforeAll {
    $script:RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))

    function Write-LogMessage { param($API, $tenant, $message, $Sev, $LogData) }
    function Get-TenantGroups { @() }
    function Get-CippTable { param($tablename) @{} }
    function ConvertTo-CIPPODataFilterValue { param($Value, $Type) "$Value" -replace "'", "''" }
    function Get-CIPPAzDataTableEntity { param($Filter) @() }
    function Get-CIPPBaseline { $script:Baselines }
    function Get-CIPPBaselineDefinition { $script:Definitions }
    function Expand-CIPPBaselineTemplatePackage { param($Definition, $Config, $TemplateRows) @() }

    . (Join-Path $script:RepoRoot 'Modules/CIPPCore/Public/Baselines/Get-CIPPBaselineWorkItems.ps1')

    $script:Definitions = @(
        [PSCustomObject]@{
            name             = 'ConditionalAccessTemplate'
            label            = 'Conditional Access Template'
            multiple         = $true
            instanceIdentity = 'caTemplate'
            variables        = [PSCustomObject]@{
                caTemplate = [PSCustomObject]@{ type = 'autoComplete'; label = 'Template' }
                state      = [PSCustomObject]@{ type = 'autoComplete'; label = 'State' }
            }
        },
        [PSCustomObject]@{
            name      = 'PlainStd'
            label     = 'Plain Standard'
            variables = [PSCustomObject]@{ value = [PSCustomObject]@{ type = 'number'; label = 'Value' } }
        }
    )

    # One baseline, tenant in the given stage. Configs arrive exactly as the editor saves
    # them: a fresh instance key per add, the template GUID in the caTemplate variable.
    $script:NewBaseline = {
        param($Stages, $CurrentStage)
        [PSCustomObject]@{
            GUID            = 'tpl-guid'
            templateName    = 'Baseline'
            assignments     = @([PSCustomObject]@{ value = 'AllTenants' })
            assignedTenants = @('AllTenants')
            excludedTenants = @()
            alertEmails     = ''
            alertWebhookUrl = ''
            disableAlerts   = $false
            disableScheduledRuns = $false
            updatedAt       = 100
            stages          = $Stages
            tenantStates    = @([PSCustomObject]@{ tenantFilter = 'contoso.com'; tenantName = 'Contoso'; currentStage = $CurrentStage })
        }
    }
    $script:CaConfig = {
        param($Instance, $Template, $State)
        [PSCustomObject]@{
            standard         = 'ConditionalAccessTemplate'
            instance         = $Instance
            variables        = [PSCustomObject]@{ caTemplate = $Template; state = $State }
            remediateEnabled = $false
            alertEnabled     = $true
            alertOnRemediate = $false
        }
    }
}

Describe 'Stage walk keys on semantic identity (issue #789)' {
    It 'later stage supersedes the earlier stage for the same template - no conflict' {
        $script:Baselines = @(& $script:NewBaseline @(
                [PSCustomObject]@{ name = 'Stage 1'; standardsConfig = @((& $script:CaConfig 'ConditionalAccessTemplate#aaa' 'tpl-1' 'enabledForReportingButNotEnforced')) },
                [PSCustomObject]@{ name = 'Stage 2'; standardsConfig = @((& $script:CaConfig 'ConditionalAccessTemplate#bbb' 'tpl-1' 'enabled')) }
            ) 2)

        $Items = @(Get-CIPPBaselineWorkItems)

        $Items.Count | Should -Be 1
        $Items[0].Conflicted | Should -Not -Be $true
        $Items[0].Standard | Should -Be 'ConditionalAccessTemplate#bbb'
        $Items[0].Variables.state | Should -Be 'enabled'
        $Items[0].Stage | Should -Be 2
        $Items[0].StageName | Should -Be 'Stage 2'
    }

    It 'different templates in different stages coexist' {
        $script:Baselines = @(& $script:NewBaseline @(
                [PSCustomObject]@{ name = 'Stage 1'; standardsConfig = @((& $script:CaConfig 'ConditionalAccessTemplate#aaa' 'tpl-1' 'enabled')) },
                [PSCustomObject]@{ name = 'Stage 2'; standardsConfig = @((& $script:CaConfig 'ConditionalAccessTemplate#bbb' 'tpl-2' 'enabled')) }
            ) 2)

        $Items = @(Get-CIPPBaselineWorkItems)

        $Items.Count | Should -Be 2
        @($Items | Where-Object { $_.Conflicted -eq $true }).Count | Should -Be 0
    }

    It 'the same template twice INSIDE one stage still conflicts' {
        $script:Baselines = @(& $script:NewBaseline @(
                [PSCustomObject]@{ name = 'Stage 1'; standardsConfig = @(
                        (& $script:CaConfig 'ConditionalAccessTemplate#aaa' 'tpl-1' 'enabled'),
                        (& $script:CaConfig 'ConditionalAccessTemplate#bbb' 'tpl-1' 'disabled')
                    )
                }
            ) 1)

        $Items = @(Get-CIPPBaselineWorkItems)

        $Items.Count | Should -Be 2
        @($Items | Where-Object { $_.Conflicted -eq $true }).Count | Should -Be 2
    }

    It 'a tenant still in stage 1 only gets the stage 1 config' {
        $script:Baselines = @(& $script:NewBaseline @(
                [PSCustomObject]@{ name = 'Stage 1'; standardsConfig = @((& $script:CaConfig 'ConditionalAccessTemplate#aaa' 'tpl-1' 'enabledForReportingButNotEnforced')) },
                [PSCustomObject]@{ name = 'Stage 2'; standardsConfig = @((& $script:CaConfig 'ConditionalAccessTemplate#bbb' 'tpl-1' 'enabled')) }
            ) 1)

        $Items = @(Get-CIPPBaselineWorkItems)

        $Items.Count | Should -Be 1
        $Items[0].Variables.state | Should -Be 'enabledForReportingButNotEnforced'
        $Items[0].Stage | Should -Be 1
    }

    It 'plain standards keep superseding across stages by instance key' {
        $PlainConfig = {
            param($Value)
            [PSCustomObject]@{
                standard         = 'PlainStd'
                instance         = 'PlainStd'
                variables        = [PSCustomObject]@{ value = $Value }
                remediateEnabled = $false
                alertEnabled     = $false
                alertOnRemediate = $false
            }
        }
        $script:Baselines = @(& $script:NewBaseline @(
                [PSCustomObject]@{ name = 'Stage 1'; standardsConfig = @((& $PlainConfig 1)) },
                [PSCustomObject]@{ name = 'Stage 2'; standardsConfig = @((& $PlainConfig 2)) }
            ) 2)

        $Items = @(Get-CIPPBaselineWorkItems)

        $Items.Count | Should -Be 1
        $Items[0].Conflicted | Should -Not -Be $true
        $Items[0].Variables.value | Should -Be 2
        $Items[0].Stage | Should -Be 2
    }
}
