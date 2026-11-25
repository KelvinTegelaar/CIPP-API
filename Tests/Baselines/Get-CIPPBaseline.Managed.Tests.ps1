# The Baselines list filters on isManaged and the Align and Merge actions read the CyberDrain id.

BeforeAll {
    $script:RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))

    function Get-CippTable { param($tablename) @{ Context = "stub-$tablename" } }
    function Get-CIPPAzDataTableEntity { param($Context, $Filter) }
    function ConvertTo-CIPPODataFilterValue { param($Value, $Type) "$Value" }
    function Get-Tenants { @() }
    function Get-TenantGroups { @() }
    function Write-LogMessage { param($API, $message, $Sev) }
    . (Join-Path $script:RepoRoot 'Modules/CIPPCore/Public/GitHub/Test-CIPPRepoSource.ps1')
    function Get-CIPPTemplateSourceUrl { param($Source, $SourcePath, $Repos) }

    . (Join-Path $script:RepoRoot 'Modules/CIPPCore/Public/Baselines/Get-CIPPBaseline.ps1')
    . (Join-Path $script:RepoRoot 'Modules/CIPPCore/Public/Get-CIPPTenantLookup.ps1')
}

Describe 'Get-CIPPBaseline managed projection' {
    It 'marks a baseline that carries a CyberDrain id as managed' {
        Mock -CommandName Get-CIPPAzDataTableEntity -MockWith {
            if ($Filter -like "*PartitionKey eq 'rollout'*") {
                @([pscustomobject]@{ RowKey = 'baseline-1'; templateName = 'Managed Baseline'; Stages = '[]'; ManagedId = 'managed-1'; ManagedVersion = '2'; ManagedKind = 'custom'; ManagedRequestId = 'request-9' })
            } else { @() }
        }

        $Result = Get-CIPPBaseline -ID 'baseline-1'

        $Result.isManaged | Should -BeTrue
        $Result.managedId | Should -Be 'managed-1'
        $Result.managedVersion | Should -Be '2'
        $Result.managedKind | Should -Be 'custom'
        $Result.managedRequestId | Should -Be 'request-9'
        $Result.isSynced | Should -BeFalse
    }

    It 'leaves an ordinary baseline unmanaged' {
        Mock -CommandName Get-CIPPAzDataTableEntity -MockWith {
            if ($Filter -like "*PartitionKey eq 'rollout'*") {
                @([pscustomobject]@{ RowKey = 'baseline-2'; templateName = 'Local Baseline'; Stages = '[]' })
            } else { @() }
        }

        (Get-CIPPBaseline -ID 'baseline-2').isManaged | Should -BeFalse
    }
}
