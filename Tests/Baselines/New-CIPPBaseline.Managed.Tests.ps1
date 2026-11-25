# A baseline CyberDrain maintains carries its CyberDrain id, version, kind and request id on the
# rollout row. Every save rewrites the whole row, so they have to be carried across an editor
# save the same way Source and SHA are. A clone gets a new id and is an ordinary baseline.

BeforeAll {
    $BackendRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))

    function Get-CippTable { param($tablename) @{ Context = "stub-$tablename" } }
    function ConvertTo-CIPPODataFilterValue { param($Value, $Type) "$Value" }
    function Get-CIPPAzDataTableEntity { param($Context, $Filter) }
    function Add-CIPPAzDataTableEntity { param($Context, $Entity) }
    function Remove-CIPPAzDataTableEntity { param($Context, $Entity, [switch]$Force) }
    function Get-TenantGroups { @() }
    function Get-Tenants { param($TenantFilter, [switch]$IncludeErrors) @() }

    . (Join-Path $BackendRoot 'Modules/CIPPCore/Public/Baselines/New-CIPPBaseline.ps1')
    . (Join-Path $BackendRoot 'Modules/CIPPCore/Public/Get-CIPPTenantLookup.ps1')

    function Get-Payload($Guid = 'baseline-1') {
        [pscustomobject]@{
            GUID            = $Guid
            templateName    = 'My Baseline'
            assignedTenants = @('AllTenants')
            stages          = @([pscustomobject]@{ name = 'Stage 1'; standards = @() })
        }
    }
    $script:ManagedRow = [pscustomobject]@{ RowKey = 'baseline-1'; ManagedId = 'managed-1'; ManagedVersion = '2'; ManagedKind = 'template'; ManagedRequestId = '' }
}

Describe 'New-CIPPBaseline managed columns' {
    BeforeEach {
        $script:RolloutWritten = $null
        Mock -CommandName Get-CIPPAzDataTableEntity -MockWith { @() }
        Mock -CommandName Add-CIPPAzDataTableEntity -MockWith {
            param($Context, $Entity)
            if ($Entity.PartitionKey -eq 'rollout') { $script:RolloutWritten = $Entity }
        }
    }

    It 'writes the id, version, kind and request id it is given' {
        $null = New-CIPPBaseline -Baseline (Get-Payload) -User 'tester' -Managed @{ Id = 'managed-1'; Version = 3; Kind = 'custom'; RequestId = 'request-9' }

        $script:RolloutWritten.ManagedId | Should -Be 'managed-1'
        $script:RolloutWritten.ManagedVersion | Should -Be '3'
        $script:RolloutWritten.ManagedKind | Should -Be 'custom'
        $script:RolloutWritten.ManagedRequestId | Should -Be 'request-9'
    }

    It 'carries them across an editor save that does not pass them' {
        Mock -CommandName Get-CIPPAzDataTableEntity -MockWith {
            if ($Context -eq 'stub-BaselineRollouts') { $script:ManagedRow }
        }

        $null = New-CIPPBaseline -Baseline (Get-Payload) -User 'tester'

        $script:RolloutWritten.ManagedId | Should -Be 'managed-1'
        $script:RolloutWritten.ManagedVersion | Should -Be '2'
        $script:RolloutWritten.ManagedKind | Should -Be 'template'
    }

    It 'takes a new version while keeping the rest when only the version changes' {
        Mock -CommandName Get-CIPPAzDataTableEntity -MockWith {
            if ($Context -eq 'stub-BaselineRollouts') { $script:ManagedRow }
        }

        $null = New-CIPPBaseline -Baseline (Get-Payload) -User 'tester' -Managed @{ Version = 5 }

        $script:RolloutWritten.ManagedId | Should -Be 'managed-1'
        $script:RolloutWritten.ManagedVersion | Should -Be '5'
        $script:RolloutWritten.ManagedKind | Should -Be 'template'
    }

    It 'writes none of them for an ordinary baseline' {
        $null = New-CIPPBaseline -Baseline (Get-Payload) -User 'tester'

        $script:RolloutWritten.ContainsKey('ManagedId') | Should -BeFalse
        $script:RolloutWritten.ContainsKey('ManagedVersion') | Should -BeFalse
    }

    It 'leaves a clone of a managed baseline unmanaged, because it is saved under a new id' {
        Mock -CommandName Get-CIPPAzDataTableEntity -MockWith {
            if ($Context -eq 'stub-BaselineRollouts' -and $Filter -like "*RowKey eq 'baseline-1'*") { $script:ManagedRow }
        }

        $null = New-CIPPBaseline -Baseline (Get-Payload 'clone-2') -User 'tester'

        $script:RolloutWritten.RowKey | Should -Be 'clone-2'
        $script:RolloutWritten.ContainsKey('ManagedId') | Should -BeFalse
    }
}
