# A pushed template's row must be stamped with the returned blob SHA and the repo FullName
# via UpsertMerge (not a full rewrite) so the next repo sync recognises this as the current
# copy instead of re-importing it as new.

BeforeAll {
    $BackendRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
    $FunctionPath = Join-Path $BackendRoot 'Modules/CIPPCore/Public/GitHub/Push-CIPPTemplateToRepo.ps1'
    $HashFunctionPath = Join-Path $BackendRoot 'Modules/CIPPCore/Public/GitHub/Get-CIPPTemplateContentHash.ps1'

    function Get-CIPPTable { param($TableName) @{ Context = "stub-$TableName" } }
    function Get-CIPPAzDataTableEntity { param($Context, $Filter) }
    function Add-CIPPAzDataTableEntity { param($Context, $Entity, [string]$OperationType) }
    function Push-GitHubContent { param($FullName, $Path, $Content, $Message, $Branch) }

    . $HashFunctionPath
    . $FunctionPath
}

Describe 'Push-CIPPTemplateToRepo' {
    BeforeEach {
        $script:Written = $null
        Mock -CommandName Get-CIPPAzDataTableEntity -MockWith {
            [pscustomobject]@{
                RowKey       = 'guid-1'
                PartitionKey = 'StandardsTemplateV2'
                JSON         = '{"templateName":"My Template","tenantFilter":[{"value":"tenant1"}]}'
            }
        }
        Mock -CommandName Push-GitHubContent -MockWith { @{ content = @{ sha = 'newsha123' } } }
        Mock -CommandName Add-CIPPAzDataTableEntity -MockWith { $script:Written = $Entity } -ParameterFilter { $OperationType -eq 'UpsertMerge' }
    }

    It 'stamps SHA and Source on the template row via UpsertMerge and returns success' {
        $Result = Push-CIPPTemplateToRepo -GUID 'guid-1' -FullName 'Org/repo' -Message 'push it' -Branch 'main'

        Should -Invoke Add-CIPPAzDataTableEntity -Times 1 -ParameterFilter { $OperationType -eq 'UpsertMerge' }
        $script:Written.PartitionKey | Should -Be 'StandardsTemplateV2'
        $script:Written.RowKey | Should -Be 'guid-1'
        $script:Written.SHA | Should -Be 'newsha123'
        $script:Written.Source | Should -Be 'Org/repo'
        $Result.state | Should -Be 'success'
    }

    It 'stamps SourcePath with the computed repo path' {
        $null = Push-CIPPTemplateToRepo -GUID 'guid-1' -FullName 'Org/repo' -Message 'push it' -Branch 'main'
        $script:Written.SourcePath | Should -Be 'StandardsTemplateV2/My_Template.json'
    }

    It 'stamps ContentHash with the hash of the pushed JSON' {
        $null = Push-CIPPTemplateToRepo -GUID 'guid-1' -FullName 'Org/repo' -Message 'push it' -Branch 'main'
        $script:Written.ContentHash | Should -Not -BeNullOrEmpty
        $script:Written.ContentHash | Should -Match '^[0-9a-f]{64}$'
    }

    It 'does not rewrite the JSON column, only stamps SHA and Source' {
        $null = Push-CIPPTemplateToRepo -GUID 'guid-1' -FullName 'Org/repo' -Message 'push it' -Branch 'main'
        $script:Written.ContainsKey('JSON') | Should -BeFalse
    }

    It 'returns an error result and does not stamp when the template is not found' {
        Mock -CommandName Get-CIPPAzDataTableEntity -MockWith { $null }
        $Result = Push-CIPPTemplateToRepo -GUID 'missing' -FullName 'Org/repo' -Message 'push it' -Branch 'main'
        $Result.state | Should -Be 'error'
        Should -Invoke Add-CIPPAzDataTableEntity -Times 0
    }

    It 'returns an error result and does not stamp when GitHub returns no blob sha' {
        Mock -CommandName Push-GitHubContent -MockWith { $null }
        $Result = Push-CIPPTemplateToRepo -GUID 'guid-1' -FullName 'Org/repo' -Message 'push it' -Branch 'main'
        $Result.state | Should -Be 'error'
        Should -Invoke Add-CIPPAzDataTableEntity -Times 0
    }
}
