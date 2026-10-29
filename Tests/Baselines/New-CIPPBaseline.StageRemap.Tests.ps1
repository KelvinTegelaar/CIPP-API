BeforeAll {
    $BackendRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))

    function Get-CippTable { param($tablename) @{ Context = "stub-$tablename" } }
    function ConvertTo-CIPPODataFilterValue { param($Value, $Type) "$Value" }
    function Get-CIPPAzDataTableEntity { param($Context, $Filter) }
    function Add-CIPPAzDataTableEntity { param($Context, $Entity, [switch]$Force) }
    function Remove-CIPPAzDataTableEntity { param($Context, $Entity, [switch]$Force) }
    function Add-CIPPBaselineHistoryEvent { param($TenantFilter, $Standard, $Mode, $TriggeredBy, $Outcome, $Detail) }
    function Write-LogMessage { param($API, $tenant, $message, $Sev, $headers) }
    function Get-TenantGroups { @() }
    function Get-Tenants { param($TenantFilter, [switch]$IncludeErrors) @() }

    . (Join-Path $BackendRoot 'Modules/CIPPCore/Public/Baselines/New-CIPPBaseline.ps1')
    . (Join-Path $BackendRoot 'Modules/CIPPCore/Public/Get-CIPPTenantLookup.ps1')

    # Saves a baseline whose editor stages came from the given saved positions ($null = new stage)
    # over tenants sitting in the given stages; returns the state rows written, keyed by tenant.
    function Invoke-StageSave {
        param([object[]]$SourceStages, [hashtable]$TenantStages)
        $script:States = @($TenantStages.GetEnumerator() | ForEach-Object {
                [pscustomobject]@{ PartitionKey = 'b1'; RowKey = $_.Key; currentStage = $_.Value; enteredStageAt = 100; firstDeployedAt = 50 }
            })
        $script:Written = @{}
        Mock -CommandName Get-CIPPAzDataTableEntity -MockWith {
            param($Context, $Filter)
            switch ($Context) {
                'stub-BaselineRollouts' { [pscustomobject]@{ RowKey = 'b1' } }
                'stub-BaselineRolloutState' { $script:States }
            }
        }
        Mock -CommandName Add-CIPPAzDataTableEntity -MockWith {
            param($Context, $Entity, [switch]$Force)
            if ($Context -eq 'stub-BaselineRolloutState') { $script:Written[$Entity.RowKey] = $Entity }
        }
        $Stage = 0
        $Payload = [pscustomobject]@{
            GUID            = 'b1'
            templateName    = 'Staged'
            assignedTenants = @('AllTenants')
            stages          = @($SourceStages | ForEach-Object { $Stage++; [pscustomobject]@{ name = "S$Stage"; sourceStage = $_; standards = @() } })
        }
        $null = New-CIPPBaseline -Baseline $Payload -User 'tester'
        $script:Written
    }
}

Describe 'New-CIPPBaseline stage remap' {
    It 'moves a tenant in a removed stage back to the previous stage, never forward' {
        $Written = Invoke-StageSave -SourceStages @(1, 3) -TenantStages @{ t1 = 2 }
        $Written.t1.currentStage | Should -Be 1
        $Written.t1.enteredStageAt | Should -Not -Be 100
    }

    It 'follows a tenant to its stage''s new position and keeps its stage clock' {
        $Written = Invoke-StageSave -SourceStages @(1, 3) -TenantStages @{ t1 = 3; t2 = 1 }
        $Written.t1.currentStage | Should -Be 2
        $Written.t1.enteredStageAt | Should -Be 100
        $Written.ContainsKey('t2') | Should -BeFalse
    }

    It 'does not hand a tenant a stage inserted or moved ahead of its own' {
        $Written = Invoke-StageSave -SourceStages @(1, $null, 2) -TenantStages @{ t1 = 2 }
        $Written.t1.currentStage | Should -Be 1
        $Written = Invoke-StageSave -SourceStages @(1, 3, 2) -TenantStages @{ t1 = 2 }
        $Written.t1.currentStage | Should -Be 1
    }

    It 'pulls a tenant left past the last stage back into range' {
        $Written = Invoke-StageSave -SourceStages @(1) -TenantStages @{ t1 = 2 }
        $Written.t1.currentStage | Should -Be 1
    }

    It 'leaves rollout state alone when the payload carries no saved stage positions' {
        $Written = Invoke-StageSave -SourceStages @($null, $null) -TenantStages @{ t1 = 3 }
        $Written.Count | Should -Be 0
    }
}
