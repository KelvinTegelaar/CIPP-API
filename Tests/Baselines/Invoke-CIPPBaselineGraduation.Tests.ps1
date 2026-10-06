BeforeAll {
    $script:RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
    . (Join-Path $script:RepoRoot 'Modules/CIPPCore/Public/Baselines/Invoke-CIPPBaselineGraduation.ps1')

    function Get-CippTable { param($tablename) @{ TableName = $tablename } }
    function Get-CIPPBaselineDefinition { @() }
    function Get-TenantGroups { param([switch]$SkipCache) }
    function Get-CIPPBaseline { param($ID) }
    function Add-CIPPAzDataTableEntity { param($TableName, $Entity, [switch]$Force) }
    function Add-CIPPBaselineHistoryEvent { param($TenantFilter, $Standard, $Mode, $TriggeredBy, $Outcome, $Detail) }
    function Write-LogMessage { param($API, $tenant, $message, $Sev) }
    function Get-CIPPAzDataTableEntity { param($TableName, $Filter) }
    function ConvertTo-CIPPODataFilterValue { param($Value) $Value }
    function Expand-CIPPBaselineTemplatePackage { param($Definition, $Config) }

    $script:Baseline = [pscustomobject]@{
        GUID         = 'b1'
        templateName = 'Rollout'
        stages       = @(
            [pscustomobject]@{ name = 'Pilot'; conditions = @() }
            [pscustomobject]@{ name = 'Intune'; logic = 'and'; conditions = @([pscustomobject]@{ type = 'group'; group = [pscustomobject]@{ value = 'g1' } }) }
        )
        tenantStates = @(
            [pscustomobject]@{ tenantFilter = 'in.onmicrosoft.com'; currentStage = 1; totalStages = 2; stageName = 'Pilot'; enteredStageAt = 1 }
            [pscustomobject]@{ tenantFilter = 'out.onmicrosoft.com'; currentStage = 1; totalStages = 2; stageName = 'Pilot'; enteredStageAt = 1 }
        )
    }
}

Describe 'Invoke-CIPPBaselineGraduation' {
    BeforeEach {
        Mock Get-CIPPBaseline { $script:Baseline }
        Mock Get-TenantGroups { [pscustomobject]@{ Id = 'g1'; Name = 'Intune'; Members = @([pscustomobject]@{ defaultDomainName = 'in.onmicrosoft.com' }) } }
        Mock Add-CIPPAzDataTableEntity {}
        Mock Add-CIPPBaselineHistoryEvent {}
    }

    It 'advances only group members and reports the unmet condition for the rest' {
        $Results = @(Invoke-CIPPBaselineGraduation)
        $Results.Count | Should -Be 2
        ($Results | Where-Object TenantFilter -EQ 'in.onmicrosoft.com').Advanced | Should -BeTrue
        $Out = $Results | Where-Object TenantFilter -EQ 'out.onmicrosoft.com'
        $Out.Advanced | Should -BeFalse
        $Out.Unmet | Should -Be @('group')
        Should -Invoke Add-CIPPAzDataTableEntity -Times 1 -ParameterFilter { $Entity.RowKey -eq 'in.onmicrosoft.com' -and $Entity.currentStage -eq 2 }
    }

    It 'scopes to one tenant and records who triggered it' {
        $Results = @(Invoke-CIPPBaselineGraduation -TenantFilter 'in.onmicrosoft.com' -TemplateId 'b1' -TriggeredBy 'admin@contoso.com')
        $Results.Count | Should -Be 1
        $Results[0].Stage | Should -Be 2
        $Results[0].StageName | Should -Be 'Intune'
        Should -Invoke Get-CIPPBaseline -Times 1 -ParameterFilter { $ID -eq 'b1' }
        Should -Invoke Add-CIPPBaselineHistoryEvent -Times 1 -ParameterFilter { $TriggeredBy -eq 'admin@contoso.com' }
    }

    Context 'success condition' {
        BeforeEach {
            $script:Baseline = [pscustomobject]@{
                GUID         = 'b2'
                templateName = 'Rollout'
                stages       = @(
                    [pscustomobject]@{ name = 'Pilot'; conditions = @(); standardsConfig = @([pscustomobject]@{ instance = 'standards.A' }, [pscustomobject]@{ instance = 'standards.B' }) }
                    [pscustomobject]@{ name = 'Next'; logic = 'and'; conditions = @([pscustomobject]@{ type = 'success' }) }
                )
                tenantStates = @([pscustomobject]@{ tenantFilter = 't.onmicrosoft.com'; currentStage = 1; totalStages = 2; stageName = 'Pilot'; enteredStageAt = 1 })
            }
            Mock Get-CIPPBaseline { $script:Baseline }
        }

        It 'treats a standard the tenant cannot license as aligned instead of blocking the stage' {
            Mock Get-CIPPAzDataTableEntity {
                @(
                    [pscustomobject]@{ StandardName = 'standards.A'; Status = 'Compliant' }
                    [pscustomobject]@{ StandardName = 'standards.B'; Status = 'Skipped - No License' }
                )
            }
            $Result = @(Invoke-CIPPBaselineGraduation -TemplateId 'b2')[0]
            $Result.Advanced | Should -BeTrue
            $Result.Stage | Should -Be 2
        }

        It 'still holds the stage while a licensable standard drifts' {
            Mock Get-CIPPAzDataTableEntity {
                @(
                    [pscustomobject]@{ StandardName = 'standards.A'; Status = 'Drift' }
                    [pscustomobject]@{ StandardName = 'standards.B'; Status = 'Skipped - No License' }
                )
            }
            $Result = @(Invoke-CIPPBaselineGraduation -TemplateId 'b2')[0]
            $Result.Advanced | Should -BeFalse
            $Result.Unmet | Should -Be @('success')
        }
    }
}
