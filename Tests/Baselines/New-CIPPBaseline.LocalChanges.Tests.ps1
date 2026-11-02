# -LocalChanges marks a synced baseline as having edits not yet pushed to its repo. Explicit
# true/false wins; when the caller does not pass it, the existing rollout row's value carries
# across untouched, same as Source/SHA/SourcePath, so an editor re-save cannot silently clear it.

BeforeAll {
    $BackendRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
    $FunctionPath = Join-Path $BackendRoot 'Modules/CIPPCore/Public/Baselines/New-CIPPBaseline.ps1'

    function Get-CippTable { param($tablename) @{ Context = "stub-$tablename" } }
    function ConvertTo-CIPPODataFilterValue { param($Value, $Type) "$Value" }
    function Get-CIPPAzDataTableEntity { param($Context, $Filter) }
    function Add-CIPPAzDataTableEntity { param($Context, $Entity) }
    function Remove-CIPPAzDataTableEntity { param($Context, $Entity, [switch]$Force) }
    function Get-TenantGroups { @() }

    . $FunctionPath

    function Get-Payload {
        [pscustomobject]@{
            GUID            = 'baseline-1'
            templateName    = 'My Baseline'
            assignedTenants = @('AllTenants')
            stages          = @([pscustomobject]@{ name = 'Stage 1'; standards = @() })
        }
    }
}

Describe 'New-CIPPBaseline LocalChanges' {
    BeforeEach {
        $script:RolloutWritten = $null
        Mock -CommandName Get-CIPPAzDataTableEntity -MockWith { @() }
        Mock -CommandName Add-CIPPAzDataTableEntity -MockWith {
            param($Context, $Entity)
            if ($Entity.PartitionKey -eq 'rollout') { $script:RolloutWritten = $Entity }
        }
    }

    It 'writes LocalChanges=$true when explicitly passed' {
        $null = New-CIPPBaseline -Baseline (Get-Payload) -User 'tester' -LocalChanges:$true
        $script:RolloutWritten.LocalChanges | Should -Be $true
    }

    It 'writes LocalChanges=$false when explicitly passed' {
        $null = New-CIPPBaseline -Baseline (Get-Payload) -User 'tester' -LocalChanges:$false
        $script:RolloutWritten.LocalChanges | Should -Be $false
    }

    It 'carries the existing rollout LocalChanges value across when not passed' {
        Mock -CommandName Get-CIPPAzDataTableEntity -MockWith {
            param($Context, $Filter)
            if ($Context -eq 'stub-BaselineRollouts') {
                @([pscustomobject]@{ RowKey = 'baseline-1'; Source = 'Org/repo'; SHA = 'abc123'; LocalChanges = $true })
            } else {
                @()
            }
        }
        $null = New-CIPPBaseline -Baseline (Get-Payload) -User 'tester'
        $script:RolloutWritten.LocalChanges | Should -Be $true
    }

    It 'writes no LocalChanges column for a brand-new baseline with no existing row and no flag passed' {
        $null = New-CIPPBaseline -Baseline (Get-Payload) -User 'tester'
        $script:RolloutWritten.ContainsKey('LocalChanges') | Should -BeFalse
    }
}
