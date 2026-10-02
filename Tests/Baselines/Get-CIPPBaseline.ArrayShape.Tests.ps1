# Issue #771: with exactly one exclusion the list API returned `exclusions` as a bare
# object instead of a one-item array. The table auto-flattened it into
# "Exclusions - Label" / "Exclusions - Value" columns, which then showed "No data" for
# every baseline with two or more exclusions. assignments had the same unrolling.

BeforeAll {
    $script:RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))

    function Get-CippTable { param($tablename) @{ Context = "stub-$tablename" } }
    function Get-CIPPAzDataTableEntity { param($Context, $Filter) }
    function ConvertTo-CIPPODataFilterValue { param($Value, $Type) "$Value" }
    function Get-Tenants { @() }
    function Get-TenantGroups { @() }
    function Write-LogMessage { param($API, $message, $Sev) }
    . (Join-Path $script:RepoRoot 'Modules/CIPPCore/Public/GitHub/Test-CIPPRepoSource.ps1')
    function Get-CIPPTemplateSourceUrl { param($Source, $SourcePath, $Repos) if ($Source) { "https://github.com/$Source" } }

    . (Join-Path $script:RepoRoot 'Modules/CIPPCore/Public/Baselines/Get-CIPPBaseline.ps1')

    # Serializes the way the HTTP layer does, so the assertions see the wire shape.
    function script:Get-WireShape {
        param($Row)
        ($Row | ConvertTo-Json -Compress -Depth 10) | ConvertFrom-Json
    }

    # Pester mock bodies run in their own scope, so the row is parked in script scope.
    function script:Set-RolloutRow {
        param([string]$ExcludedTo, [string]$ExcludedTenants, [string]$AssignedTo)
        $script:RolloutRow = [pscustomobject]@{
            RowKey          = 'baseline-1'
            templateName    = 'Shape Baseline'
            Stages          = '[]'
            excludedTo      = $ExcludedTo
            excludedTenants = $ExcludedTenants
            assignedTo      = $AssignedTo
        }
        Mock -CommandName Get-CIPPAzDataTableEntity -MockWith {
            param($Context, $Filter)
            if ($Filter -like "*PartitionKey eq 'rollout'*") { @($script:RolloutRow) } else { @() }
        }
    }
}

Describe 'Get-CIPPBaseline exclusions/assignments wire shape (#771)' {
    It 'keeps a single exclusion as a one-item array' {
        Set-RolloutRow -ExcludedTo '[{"label":"Group One","value":"g1","type":"Group"}]' -ExcludedTenants '["g1"]' -AssignedTo '[]'
        $Wire = Get-WireShape (Get-CIPPBaseline -ID 'baseline-1')
        ,$Wire.exclusions | Should -BeOfType [System.Array]
        $Wire.exclusions.Count | Should -Be 1
        $Wire.exclusions[0].label | Should -Be 'Group One'
    }

    It 'keeps two exclusions as a two-item array with their labels' {
        Set-RolloutRow -ExcludedTo '[{"label":"Group One","value":"g1","type":"Group"},{"label":"Group Two","value":"g2","type":"Group"}]' -ExcludedTenants '["g1","g2"]' -AssignedTo '[]'
        $Wire = Get-WireShape (Get-CIPPBaseline -ID 'baseline-1')
        $Wire.exclusions.Count | Should -Be 2
        $Wire.exclusions.label | Should -Be @('Group One', 'Group Two')
    }

    It 'rebuilds a one-item array from legacy flat excludedTenants when excludedTo is absent' {
        Set-RolloutRow -ExcludedTo $null -ExcludedTenants '["contoso.onmicrosoft.com"]' -AssignedTo $null
        $Wire = Get-WireShape (Get-CIPPBaseline -ID 'baseline-1')
        ,$Wire.exclusions | Should -BeOfType [System.Array]
        $Wire.exclusions.Count | Should -Be 1
        $Wire.exclusions[0].value | Should -Be 'contoso.onmicrosoft.com'
    }

    It 'returns an empty array, not null, when nothing is excluded' {
        Set-RolloutRow -ExcludedTo '[]' -ExcludedTenants '[]' -AssignedTo '[]'
        $Wire = Get-WireShape (Get-CIPPBaseline -ID 'baseline-1')
        ,$Wire.exclusions | Should -BeOfType [System.Array]
        $Wire.exclusions.Count | Should -Be 0
    }

    It 'keeps a single assignment as a one-item array' {
        Set-RolloutRow -ExcludedTo '[]' -ExcludedTenants '[]' -AssignedTo '[{"label":"*All Tenants* (AllTenants)","value":"AllTenants","type":"Tenant"}]'
        $Wire = Get-WireShape (Get-CIPPBaseline -ID 'baseline-1')
        ,$Wire.assignments | Should -BeOfType [System.Array]
        $Wire.assignments.Count | Should -Be 1
        $Wire.assignments[0].value | Should -Be 'AllTenants'
    }
}
