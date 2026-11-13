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
    . (Join-Path $BackendRoot 'Modules/CIPPCore/Public/Get-CIPPTemplateLink.ps1')
    . (Join-Path $BackendRoot 'Modules/CIPPCore/Public/ConvertTo-CIPPODataFilterValue.ps1')
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

    It 'throws ItemNotFoundException and does not stamp when the template is not found' {
        Mock -CommandName Get-CIPPAzDataTableEntity -MockWith { $null }
        { Push-CIPPTemplateToRepo -GUID 'missing' -FullName 'Org/repo' -Message 'push it' -Branch 'main' } |
            Should -Throw -ExceptionType ([System.Management.Automation.ItemNotFoundException]) -ExpectedMessage "Template 'missing' not found"
        Should -Invoke Add-CIPPAzDataTableEntity -Times 0
    }

    It 'returns an error result and does not stamp when GitHub returns no blob sha' {
        Mock -CommandName Push-GitHubContent -MockWith { $null }
        $Result = Push-CIPPTemplateToRepo -GUID 'guid-1' -FullName 'Org/repo' -Message 'push it' -Branch 'main'
        $Result.state | Should -Be 'error'
        Should -Invoke Add-CIPPAzDataTableEntity -Times 0
    }
}

Describe 'Push-CIPPTemplateToRepo with linked templates' {
    BeforeEach {
        $script:Pushed = [System.Collections.Generic.List[object]]::new()
        Mock -CommandName Get-CIPPAzDataTableEntity -MockWith {
            [pscustomobject]@{ RowKey = 'ca-1'; PartitionKey = 'CATemplate'; JSON = '{"displayName":"Staff web filtering","sessionControls":{"globalSecureAccessFilteringProfile":{"profileId":{"label":"Staff","value":"prof-1"},"isEnabled":true}}}' }
        } -ParameterFilter { $Filter -like "*'ca-1'*" }
        Mock -CommandName Get-CIPPAzDataTableEntity -MockWith {
            [pscustomobject]@{ RowKey = 'prof-1'; PartitionKey = 'GSASecurityProfileTemplate'; JSON = '{"name":"Staff","policies":[{"policy":{"label":"Block risky","value":"pol-1"}},{"policy":{"label":"Block social","value":"pol-2"}}]}' }
        } -ParameterFilter { $Filter -like "*'GSASecurityProfileTemplate'*'prof-1'*" }
        Mock -CommandName Get-CIPPAzDataTableEntity -MockWith { [pscustomobject]@{ RowKey = 'pol-1'; PartitionKey = 'GSAFilteringPolicyTemplate'; JSON = '{"name":"Block risky"}' } } -ParameterFilter { $Filter -like "*'GSAFilteringPolicyTemplate'*'pol-1'*" }
        Mock -CommandName Get-CIPPAzDataTableEntity -MockWith { [pscustomobject]@{ RowKey = 'pol-2'; PartitionKey = 'GSAFilteringPolicyTemplate'; JSON = '{"name":"Block social"}' } } -ParameterFilter { $Filter -like "*'GSAFilteringPolicyTemplate'*'pol-2'*" }
        Mock -CommandName Push-GitHubContent -MockWith { $script:Pushed.Add([pscustomobject]@{ Path = $Path; Content = $Content }); @{ content = @{ sha = "sha-$Path" } } }
        Mock -CommandName Add-CIPPAzDataTableEntity -MockWith {}
    }

    It 'pushes the templates the CA template links first, then the CA template with a manifest of them' {
        $Result = Push-CIPPTemplateToRepo -GUID 'ca-1' -FullName 'Org/repo' -Message 'push it' -Branch 'main'
        @($script:Pushed.Path) | Should -Be @('GSASecurityProfileTemplate/Staff.json', 'GSAFilteringPolicyTemplate/Block_risky.json', 'GSAFilteringPolicyTemplate/Block_social.json', 'CATemplate/Staff_web_filtering.json')
        $Manifest = ($script:Pushed[3].Content | ConvertFrom-Json).LinkedTemplates | ConvertFrom-Json
        @($Manifest | ForEach-Object { "$($_.partition)|$($_.guid)|$($_.path)" }) | Should -Be @(
            'GSASecurityProfileTemplate|prof-1|GSASecurityProfileTemplate/Staff.json'
            'GSAFilteringPolicyTemplate|pol-1|GSAFilteringPolicyTemplate/Block_risky.json'
            'GSAFilteringPolicyTemplate|pol-2|GSAFilteringPolicyTemplate/Block_social.json'
        )
        foreach ($Pushed in $script:Pushed[0..2]) { ($Pushed.Content | ConvertFrom-Json).PSObject.Properties.Name | Should -Not -Contain 'LinkedTemplates' }
        Should -Invoke Add-CIPPAzDataTableEntity -Times 4 -Exactly -ParameterFilter { $OperationType -eq 'UpsertMerge' }
        $Result.resultText | Should -Be "Template 'Staff web filtering' uploaded with 3 linked template(s)"
    }

    It 'does not push the CA template when a template it links fails to push' {
        Mock -CommandName Push-GitHubContent -MockWith { $script:Pushed.Add([pscustomobject]@{ Path = $Path }); $null } -ParameterFilter { $Path -like 'GSAFilteringPolicyTemplate/*' }
        $Result = Push-CIPPTemplateToRepo -GUID 'ca-1' -FullName 'Org/repo' -Message 'push it' -Branch 'main'
        $Result.state | Should -Be 'error'
        $Result.resultText | Should -BeLike "Template 'Block risky', which this template links, was not pushed*"
        @($script:Pushed.Path) | Should -Not -Contain 'CATemplate/Staff_web_filtering.json'
    }

    It 'pushes a template that links nothing as before, without a manifest' {
        Mock -CommandName Get-CIPPAzDataTableEntity -MockWith { [pscustomobject]@{ RowKey = 'pol-1'; PartitionKey = 'GSAFilteringPolicyTemplate'; JSON = '{"name":"Block risky"}' } } -ParameterFilter { $Filter -like "*'pol-1'*" }
        $null = Push-CIPPTemplateToRepo -GUID 'pol-1' -FullName 'Org/repo' -Message 'push it' -Branch 'main'
        @($script:Pushed.Path) | Should -Be @('GSAFilteringPolicyTemplate/Block_risky.json')
        ($script:Pushed[0].Content | ConvertFrom-Json).PSObject.Properties.Name | Should -Not -Contain 'LinkedTemplates'
    }
}
