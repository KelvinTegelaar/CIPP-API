# A graduation condition added in the editor but left without a type was stored as {}.
# The HTTP layer serializes an empty object as null, and the baseline editor then crashed
# reading null.type, so the baseline could no longer be opened.

BeforeAll {
    $BackendRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))

    function Get-CippTable { param($tablename) @{ Context = "stub-$tablename" } }
    function ConvertTo-CIPPODataFilterValue { param($Value, $Type) "$Value" }
    function Get-CIPPAzDataTableEntity { param($Context, $Filter) }
    function Add-CIPPAzDataTableEntity { param($Context, $Entity) }
    function Remove-CIPPAzDataTableEntity { param($Context, $Entity, [switch]$Force) }
    function Get-TenantGroups { @() }
    function Get-Tenants { param($TenantFilter, [switch]$IncludeErrors) @() }
    function Write-LogMessage { param($API, $message, $Sev) }
    . (Join-Path $BackendRoot 'Modules/CIPPCore/Public/GitHub/Test-CIPPRepoSource.ps1')
    function Get-CIPPTemplateSourceUrl { param($Source, $SourcePath, $Repos) }

    . (Join-Path $BackendRoot 'Modules/CIPPCore/Public/Baselines/New-CIPPBaseline.ps1')
    . (Join-Path $BackendRoot 'Modules/CIPPCore/Public/Baselines/Get-CIPPBaseline.ps1')
    . (Join-Path $BackendRoot 'Modules/CIPPCore/Public/Get-CIPPTenantLookup.ps1')
}

Describe 'Baseline stage conditions without a type' {
    It 'drops them when the baseline is saved' {
        $script:RolloutWritten = $null
        Mock -CommandName Get-CIPPAzDataTableEntity -MockWith { @() }
        Mock -CommandName Add-CIPPAzDataTableEntity -MockWith {
            param($Context, $Entity)
            if ($Entity.PartitionKey -eq 'rollout') { $script:RolloutWritten = $Entity }
        }
        $Payload = '{"templateName":"MFA","assignedTenants":[],"stages":[{"name":"S1","conditions":[],"standards":[]},{"name":"S2","conditions":[{"type":"manual","unit":"days"},{}],"standards":[]}]}' | ConvertFrom-Json

        $null = New-CIPPBaseline -Baseline $Payload -User 'tester'

        $script:RolloutWritten.Stages | Should -Be '[{"name":"S1","logic":"and","conditions":[]},{"name":"S2","logic":"and","conditions":[{"type":"manual","unit":"days"}]}]'
    }

    It 'drops them from an already-stored baseline when it is read' {
        Mock -CommandName Get-CIPPAzDataTableEntity -MockWith {
            param($Context, $Filter)
            if ($Filter -like "*PartitionKey eq 'rollout'*") {
                [pscustomobject]@{
                    RowKey       = 'baseline-1'
                    templateName = 'MFA'
                    Stages       = '[{"name":"S1","logic":"and","conditions":[]},{"name":"S2","logic":"and","conditions":[{"type":"manual","unit":"days"},{}]}]'
                    assignedTo   = '[]'
                    excludedTo   = '[]'
                }
            }
        }

        $Baseline = Get-CIPPBaseline -ID 'baseline-1'

        $Baseline.stages[1].conditions.Count | Should -Be 1
        $Baseline.stages[1].conditions[0].type | Should -Be 'manual'
    }
}
