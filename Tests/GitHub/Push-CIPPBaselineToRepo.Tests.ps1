# A pushed baseline stamps every related template row plus the rollout row with the blob
# SHA and repo FullName returned for that push, so the next sync recognises each as current.

BeforeAll {
    $BackendRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
    $FunctionPath = Join-Path $BackendRoot 'Modules/CIPPCore/Public/GitHub/Push-CIPPBaselineToRepo.ps1'
    $HashFunctionPath = Join-Path $BackendRoot 'Modules/CIPPCore/Public/GitHub/Get-CIPPTemplateContentHash.ps1'

    function Get-CIPPTable { param($TableName) @{ Context = "stub-$TableName" } }
    function Get-CIPPAzDataTableEntity { param($Context, $Filter) }
    function Add-CIPPAzDataTableEntity { param($Context, $Entity, [string]$OperationType) }
    function Push-GitHubContent { param($FullName, $Path, $Content, $Message, $Branch) }
    function Export-CIPPBaselineTemplate { param($GUID) }

    . $HashFunctionPath
    . $FunctionPath
}

Describe 'Push-CIPPBaselineToRepo' {
    BeforeEach {
        $script:WrittenEntities = [System.Collections.Generic.List[object]]::new()
        Mock -CommandName Export-CIPPBaselineTemplate -MockWith {
            @{
                Baseline  = [pscustomobject]@{ templateName = 'My Baseline' }
                Templates = @(
                    [pscustomobject]@{ RowKey = 'tpl-1'; PartitionKey = 'CATemplate'; JSON = '{"displayName":"CA One"}' }
                    [pscustomobject]@{ RowKey = 'tpl-2'; PartitionKey = 'IntuneTemplate'; JSON = '{"displayName":"Intune One"}' }
                    [pscustomobject]@{ RowKey = 'tpl-3'; PartitionKey = 'StandardsTemplateV2'; JSON = '{"templateName":"Standards One"}' }
                )
            }
        }
        Mock -CommandName Push-GitHubContent -MockWith { @{ content = @{ sha = "sha-for-$($Path)" } } }
        Mock -CommandName Add-CIPPAzDataTableEntity -MockWith { $script:WrittenEntities.Add($Entity) }
    }

    It 'stamps every related template row and the rollout row' {
        $Result = Push-CIPPBaselineToRepo -GUID 'baseline-1' -FullName 'Org/repo' -Message 'push it' -Branch 'main'

        $Result.state | Should -Be 'success'
        $script:WrittenEntities.Count | Should -Be 4

        $Tpl1 = $script:WrittenEntities | Where-Object { $_.PartitionKey -eq 'CATemplate' }
        $Tpl1.RowKey | Should -Be 'tpl-1'
        $Tpl1.Source | Should -Be 'Org/repo'
        $Tpl1.SHA | Should -Not -BeNullOrEmpty
        $Tpl1.SourcePath | Should -Be 'CATemplate/CA_One.json'
        $Tpl1.ContainsKey('ContentHash') | Should -BeFalse

        $Tpl2 = $script:WrittenEntities | Where-Object { $_.PartitionKey -eq 'IntuneTemplate' }
        $Tpl2.RowKey | Should -Be 'tpl-2'
        $Tpl2.SourcePath | Should -Be 'IntuneTemplate/Intune_One.json'
        $Tpl2.ContainsKey('ContentHash') | Should -BeFalse

        $Tpl3 = $script:WrittenEntities | Where-Object { $_.PartitionKey -eq 'StandardsTemplateV2' }
        $Tpl3.RowKey | Should -Be 'tpl-3'
        $Tpl3.ContentHash | Should -Not -BeNullOrEmpty
        $Tpl3.ContentHash | Should -Match '^[0-9a-f]{64}$'

        $Rollout = $script:WrittenEntities | Where-Object { $_.PartitionKey -eq 'rollout' }
        $Rollout.RowKey | Should -Be 'baseline-1'
        $Rollout.Source | Should -Be 'Org/repo'
        $Rollout.SHA | Should -Not -BeNullOrEmpty
        $Rollout.SourcePath | Should -Be 'BaselineTemplate/My_Baseline.json'
        $Rollout.LocalChanges | Should -Be $false
    }

    It 'returns an error result when the baseline does not exist' {
        Mock -CommandName Export-CIPPBaselineTemplate -MockWith { $null }
        $Result = Push-CIPPBaselineToRepo -GUID 'missing' -FullName 'Org/repo' -Message 'push it' -Branch 'main'
        $Result.state | Should -Be 'error'
        Should -Invoke Add-CIPPAzDataTableEntity -Times 0
    }

    It 'returns an error result and stamps nothing when GitHub returns no blob sha' {
        Mock -CommandName Push-GitHubContent -MockWith { $null }
        $Result = Push-CIPPBaselineToRepo -GUID 'baseline-1' -FullName 'Org/repo' -Message 'push it' -Branch 'main'
        $Result.state | Should -Be 'error'
        $script:WrittenEntities.Count | Should -Be 0
    }
}
