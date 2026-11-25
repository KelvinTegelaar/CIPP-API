# Align makes a managed baseline's standards identical to CyberDrain's. Merge overwrites what
# both sides have, keeps the partner's own standards, and adds a CyberDrain-only standard only
# when the partner ticked it. Neither touches the name, the tenants or the alerting.

BeforeAll {
    $BackendRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
    . (Join-Path $BackendRoot 'Modules/CIPPCore/Public/Baselines/Merge-CIPPManagedBaseline.ps1')

    $script:Definitions = @(
        [pscustomobject]@{ name = 'SmartLockout'; label = 'Configure Smart Lockout'; variables = [pscustomobject]@{ LockoutThreshold = [pscustomobject]@{ type = 'number'; default = 10 } } }
        [pscustomobject]@{ name = 'OauthConsent'; label = 'Require admin consent' }
        [pscustomobject]@{ name = 'EnableFIDO2'; label = 'Enable FIDO2' }
        [pscustomobject]@{ name = 'DisableReshare'; label = 'Disable Re-sharing' }
        [pscustomobject]@{ name = 'ConditionalAccessTemplate'; label = 'Conditional Access Template'; multiple = $true; instanceIdentity = 'caTemplate'; variables = [pscustomobject]@{ caTemplate = [pscustomobject]@{ type = 'autoComplete'; required = $true } } }
    )

    function New-Config {
        param($Standard, $Variables = @{}, [bool]$Remediate = $false, $Instance)
        [pscustomobject]@{
            standard         = ($Standard -split '#')[0]
            instance         = ($Instance ?? $Standard)
            variables        = [pscustomobject]$Variables
            remediateEnabled = $Remediate
            alertEnabled     = $true
            alertOnRemediate = $false
        }
    }
    function New-LocalBaseline {
        param($Stages, $Assignments = @([pscustomobject]@{ label = 'Contoso (contoso.com)'; value = 'contoso.com'; type = 'Tenant' }))
        [pscustomobject]@{
            GUID                 = 'baseline-1'
            templateName         = 'Contoso baseline'
            description          = 'Renamed by the partner'
            assignments          = $Assignments
            exclusions           = @()
            alertEmails          = 'soc@partner.example'
            alertWebhookUrl      = ''
            disableAlerts        = $false
            disableScheduledRuns = $true
            stages               = @(foreach ($Stage in $Stages) {
                    [pscustomobject]@{ name = $Stage.name; logic = 'and'; conditions = @($Stage.conditions | Where-Object { $_ }); conditionGroups = @(); standards = @($Stage.configs.instance); standardsConfig = @($Stage.configs) }
                })
        }
    }
    function New-RemoteBaseline {
        param($Stages)
        [pscustomobject]@{
            templateName = 'CyberDrain Essentials'
            description  = 'Published by CyberDrain'
            stages       = @(foreach ($Stage in $Stages) {
                    [pscustomobject]@{ name = $Stage.name; logic = 'and'; conditions = @($Stage.conditions | Where-Object { $_ }); conditionGroups = @($Stage.conditionGroups | Where-Object { $_ }); standards = @($Stage.configs) }
                })
        }
    }
    function Invoke-Plan {
        param($Local, $Remote, $Mode, [string[]]$Add = @())
        Merge-CIPPManagedBaseline -Local $Local -Remote $Remote -Mode $Mode -Add $Add -Definitions $script:Definitions
    }
}

Describe 'Merge-CIPPManagedBaseline merge' {
    It 'overwrites a standard both sides have and says what changes' {
        $Local = New-LocalBaseline @(@{ name = 'Baseline'; configs = @(New-Config 'SmartLockout' @{ LockoutThreshold = 5 }) })
        $Remote = New-RemoteBaseline @(@{ name = 'Baseline'; configs = @(New-Config 'SmartLockout' @{ LockoutThreshold = 10 } $true) })

        $Plan = Invoke-Plan $Local $Remote 'merge'

        $Plan.Changes.overwritten.Count | Should -Be 1
        $Plan.Changes.overwritten[0].label | Should -Be 'Configure Smart Lockout'
        $Plan.Changes.overwritten[0].changes | Should -Be @('Settings', 'Automatic remediation: off to on')
        $Written = $Plan.Payload.stages[0].standards[0]
        $Written.variables.LockoutThreshold | Should -Be 10
        $Written.remediateEnabled | Should -BeTrue
    }

    It 'reads <Name> as the same as the declared default' -ForEach @(
        @{ Name = 'a blank setting'; Variables = @{} }
        @{ Name = 'the default typed as text'; Variables = @{ LockoutThreshold = '10' } }
        @{ Name = 'the default in an option wrapper'; Variables = @{ LockoutThreshold = [pscustomobject]@{ label = 'Ten'; value = 10 } } }
    ) {
        $Local = New-LocalBaseline @(@{ name = 'Baseline'; configs = @(New-Config 'SmartLockout' $Variables) })
        $Remote = New-RemoteBaseline @(@{ name = 'Baseline'; configs = @(New-Config 'SmartLockout' @{ LockoutThreshold = 10 }) })

        $Plan = Invoke-Plan $Local $Remote 'merge'

        $Plan.Changes.unchanged | Should -Be 1
        $Plan.Changes.overwritten.Count | Should -Be 0
    }

    It 'keeps a standard only the partner has' {
        $Local = New-LocalBaseline @(@{ name = 'Baseline'; configs = @((New-Config 'SmartLockout'), (New-Config 'DisableReshare' @{} $true)) })
        $Remote = New-RemoteBaseline @(@{ name = 'Baseline'; configs = @(New-Config 'SmartLockout') })

        $Plan = Invoke-Plan $Local $Remote 'merge'

        $Plan.Changes.kept.standard | Should -Be @('DisableReshare')
        $Plan.Payload.stages[0].standards.standard | Should -Be @('SmartLockout', 'DisableReshare')
        ($Plan.Payload.stages[0].standards | Where-Object { $_.standard -eq 'DisableReshare' }).remediateEnabled | Should -BeTrue
    }

    It 'leaves a CyberDrain-only standard out until it is ticked' {
        $Local = New-LocalBaseline @(@{ name = 'Baseline'; configs = @(New-Config 'SmartLockout') })
        $Remote = New-RemoteBaseline @(@{ name = 'Baseline'; configs = @((New-Config 'SmartLockout'), (New-Config 'EnableFIDO2')) })

        $Unticked = Invoke-Plan $Local $Remote 'merge'
        $Unticked.Changes.available.key | Should -Be @('EnableFIDO2|1')
        $Unticked.Changes.added.Count | Should -Be 0
        $Unticked.Payload.stages[0].standards.standard | Should -Be @('SmartLockout')

        $Ticked = Invoke-Plan $Local $Remote 'merge' @('EnableFIDO2|1')
        $Ticked.Changes.added.key | Should -Be @('EnableFIDO2|1')
        $Ticked.Changes.available.Count | Should -Be 0
        $Ticked.Payload.stages[0].standards.standard | Should -Be @('SmartLockout', 'EnableFIDO2')
    }

    It 'adds a ticked standard to the stage with the same name, else the same position, never past the last' {
        $Local = New-LocalBaseline @(
            @{ name = 'Baseline'; configs = @(New-Config 'SmartLockout') }
            @{ name = 'Hardening'; configs = @() }
        )
        $Remote = New-RemoteBaseline @(
            @{ name = 'Pilot'; configs = @((New-Config 'SmartLockout'), (New-Config 'OauthConsent')) }
            @{ name = 'Hardening'; configs = @(New-Config 'EnableFIDO2') }
            @{ name = 'Extra'; configs = @(New-Config 'DisableReshare') }
        )

        $Plan = Invoke-Plan $Local $Remote 'merge' @('OauthConsent|1', 'EnableFIDO2|1', 'DisableReshare|1')

        $Plan.Payload.stages.name | Should -Be @('Baseline', 'Hardening')
        $Plan.Payload.stages[0].standards.standard | Should -Be @('SmartLockout', 'OauthConsent')
        $Plan.Payload.stages[1].standards.standard | Should -Be @('EnableFIDO2', 'DisableReshare')
        ($Plan.Changes.added | Where-Object { $_.standard -eq 'DisableReshare' }).stage | Should -Be 'Hardening'
    }

    It 'keeps the local stages, their conditions and everything about the baseline itself' {
        $GroupCondition = [pscustomobject]@{ type = 'group'; group = 'group-1'; groupName = 'Pilot tenants' }
        $Local = New-LocalBaseline @(
            @{ name = 'Baseline'; configs = @(New-Config 'SmartLockout' @{ LockoutThreshold = 5 }) }
            @{ name = 'Wave two'; configs = @(); conditions = @($GroupCondition) }
        )
        $Remote = New-RemoteBaseline @(@{ name = 'Baseline'; configs = @(New-Config 'SmartLockout') })

        $Payload = (Invoke-Plan $Local $Remote 'merge').Payload

        $Payload.GUID | Should -Be 'baseline-1'
        $Payload.templateName | Should -Be 'Contoso baseline'
        $Payload.description | Should -Be 'Renamed by the partner'
        $Payload.assignedTenants.value | Should -Be @('contoso.com')
        $Payload.alertEmails | Should -Be 'soc@partner.example'
        $Payload.disableScheduledRuns | Should -BeTrue
        $Payload.stages.name | Should -Be @('Baseline', 'Wave two')
        $Payload.stages.sourceStage | Should -Be @(1, 2)
        $Payload.stages[1].conditions[0].type | Should -Be 'group'
    }

    It 'pairs a standard that sits in two stages in stage order' {
        $Local = New-LocalBaseline @(
            @{ name = 'Report'; configs = @(New-Config 'SmartLockout' @{ LockoutThreshold = 5 }) }
            @{ name = 'Enforce'; configs = @(New-Config 'SmartLockout' @{ LockoutThreshold = 10 } $true) }
        )
        $Remote = New-RemoteBaseline @(
            @{ name = 'Report'; configs = @(New-Config 'SmartLockout' @{ LockoutThreshold = 10 }) }
            @{ name = 'Enforce'; configs = @(New-Config 'SmartLockout' @{ LockoutThreshold = 10 } $true) }
        )

        $Plan = Invoke-Plan $Local $Remote 'merge'

        $Plan.Changes.overwritten.key | Should -Be @('SmartLockout|1')
        $Plan.Changes.overwritten[0].stage | Should -Be 'Report'
        $Plan.Changes.unchanged | Should -Be 1
    }

    It 'matches a template-backed standard on the template it points at and keeps the local instance key' {
        $LocalPicker = [pscustomobject]@{ label = 'Block legacy authentication'; value = 'tpl-1' }
        $Local = New-LocalBaseline @(@{ name = 'Baseline'; configs = @(New-Config 'ConditionalAccessTemplate' @{ caTemplate = $LocalPicker } $false 'ConditionalAccessTemplate#m11') })
        $Remote = New-RemoteBaseline @(@{ name = 'Baseline'; configs = @(
                    (New-Config 'ConditionalAccessTemplate' @{ caTemplate = 'tpl-1' } $true 'ConditionalAccessTemplate#1')
                    (New-Config 'ConditionalAccessTemplate' @{ caTemplate = 'tpl-2' } $false 'ConditionalAccessTemplate#2')
                ) })

        $Plan = Invoke-Plan $Local $Remote 'merge'

        $Plan.Changes.overwritten.key | Should -Be @('ConditionalAccessTemplate#tpl-1|1')
        $Plan.Changes.available.key | Should -Be @('ConditionalAccessTemplate#tpl-2|1')
        $Plan.Payload.stages[0].standards[0].instance | Should -Be 'ConditionalAccessTemplate#m11'
        $Plan.Payload.stages[0].standards[0].remediateEnabled | Should -BeTrue
        $Plan.TemplateIds | Should -Be @('tpl-1')
    }
}

Describe 'Merge-CIPPManagedBaseline align' {
    It 'makes the standards identical to CyberDrain and removes the ones only the partner has' {
        $Local = New-LocalBaseline @(@{ name = 'Baseline'; configs = @((New-Config 'SmartLockout' @{ LockoutThreshold = 5 }), (New-Config 'DisableReshare')) })
        $Remote = New-RemoteBaseline @(@{ name = 'Baseline'; configs = @((New-Config 'SmartLockout' @{ LockoutThreshold = 10 }), (New-Config 'EnableFIDO2')) })

        $Plan = Invoke-Plan $Local $Remote 'align'

        $Plan.Changes.overwritten.standard | Should -Be @('SmartLockout')
        $Plan.Changes.removed.standard | Should -Be @('DisableReshare')
        $Plan.Changes.added.standard | Should -Be @('EnableFIDO2')
        $Plan.Changes.available.Count | Should -Be 0
        $Plan.Payload.stages[0].standards.standard | Should -Be @('SmartLockout', 'EnableFIDO2')
        $Plan.Payload.stages[0].standards[0].variables.LockoutThreshold | Should -Be 10
    }

    It 'takes the stage layout from CyberDrain and keeps everything about the baseline itself' {
        $Local = New-LocalBaseline @(@{ name = 'Baseline'; configs = @(New-Config 'SmartLockout') })
        $Remote = New-RemoteBaseline @(
            @{ name = 'Baseline'; configs = @(New-Config 'SmartLockout') }
            @{ name = 'Hardening'; configs = @(New-Config 'EnableFIDO2') }
        )

        $Plan = Invoke-Plan $Local $Remote 'align'

        $Plan.Payload.stages.name | Should -Be @('Baseline', 'Hardening')
        $Plan.Payload.stages[0].sourceStage | Should -Be 1
        $Plan.Payload.stages[1].sourceStage | Should -BeNullOrEmpty
        $Plan.Changes.stages.from | Should -Be @('Baseline')
        $Plan.Changes.stages.to | Should -Be @('Baseline', 'Hardening')
        $Plan.Payload.templateName | Should -Be 'Contoso baseline'
        $Plan.Payload.assignedTenants.value | Should -Be @('contoso.com')
        $Plan.Payload.alertEmails | Should -Be 'soc@partner.example'
    }

    It 'keeps tenant progress by name where a stage kept its name and by position where it was renamed' {
        $Local = New-LocalBaseline @(
            @{ name = 'Pilot'; configs = @(New-Config 'SmartLockout') }
            @{ name = 'Everyone'; configs = @() }
        )
        $Remote = New-RemoteBaseline @(
            @{ name = 'Report only'; configs = @(New-Config 'SmartLockout') }
            @{ name = 'Everyone'; configs = @() }
        )

        (Invoke-Plan $Local $Remote 'align').Payload.stages.sourceStage | Should -Be @(1, 2)
    }

    It 'drops stage conditions that point at the partner''s own groups or variables' {
        $Local = New-LocalBaseline @(@{ name = 'Baseline'; configs = @(New-Config 'SmartLockout') })
        $Remote = New-RemoteBaseline @(
            @{ name = 'Baseline'; configs = @(New-Config 'SmartLockout') }
            @{
                name            = 'Hardening'
                configs         = @()
                conditions      = @(
                    [pscustomobject]@{ type = 'time'; days = 14 }
                    [pscustomobject]@{ type = 'group'; group = 'group-1' }
                    [pscustomobject]@{ type = 'variable'; variable = 'Tier'; operator = 'eq'; value = 'Gold' }
                )
                conditionGroups = @(
                    [pscustomobject]@{ logic = 'and'; conditions = @([pscustomobject]@{ type = 'group'; group = 'group-2' }) }
                    [pscustomobject]@{ logic = 'or'; conditions = @([pscustomobject]@{ type = 'manual' }, [pscustomobject]@{ type = 'variable'; variable = 'Tier' }) }
                )
            }
        )

        $Stage = (Invoke-Plan $Local $Remote 'align').Payload.stages[1]

        $Stage.conditions.type | Should -Be @('time')
        $Stage.conditionGroups.Count | Should -Be 1
        $Stage.conditionGroups[0].logic | Should -Be 'or'
        $Stage.conditionGroups[0].conditions.type | Should -Be @('manual')
    }

    It 'names every template CyberDrain refers to' {
        $Local = New-LocalBaseline @(@{ name = 'Baseline'; configs = @(New-Config 'SmartLockout') })
        $Remote = New-RemoteBaseline @(@{ name = 'Baseline'; configs = @(
                    (New-Config 'ConditionalAccessTemplate' @{ caTemplate = 'tpl-1' } $false 'ConditionalAccessTemplate#1')
                    (New-Config 'ConditionalAccessTemplate' @{ caTemplate = 'tpl-2' } $false 'ConditionalAccessTemplate#2')
                ) })

        (Invoke-Plan $Local $Remote 'align').TemplateIds | Sort-Object | Should -Be @('tpl-1', 'tpl-2')
    }

    It 'falls back to the placeholder assignment when the baseline has no tenant, so its standards are not lost' {
        $Local = New-LocalBaseline @(@{ name = 'Baseline'; configs = @(New-Config 'SmartLockout') }) -Assignments @()
        $Remote = New-RemoteBaseline @(@{ name = 'Baseline'; configs = @(New-Config 'SmartLockout') })

        (Invoke-Plan $Local $Remote 'align').Payload.assignedTenants.value | Should -Be @('Exported Template')
    }
}
