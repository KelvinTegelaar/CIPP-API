# On-read upgrade of legacy single-instance rows (AppDeploy and any future single -> multi
# conversion). A delta row saved before its definition became multi-instance holds the old
# multi-select ARRAY in the identity variable; Get-CIPPBaseline fans it out into one config
# per selected value with the migration's stable '#m<hash>' instance keys, so every consumer
# (editor, work items, export) sees the modern shape and the next save persists it. A row
# that already carries its own instance key always wins over a fanned-out duplicate.

BeforeAll {
    $script:RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))

    function Write-LogMessage { param($API, $tenant, $message, $Sev, $LogData) }
    function Get-CippTable { param($tablename) @{ Table = $tablename } }
    function ConvertTo-CIPPODataFilterValue { param($Value, $Type) "$Value" -replace "'", "''" }
    function Get-Tenants { @() }
    function Get-TenantGroups { @() }
    function Test-CIPPRepoSource { param($Source) $false }
    function Get-CIPPTemplateSourceUrl { param($Source, $SourcePath, $Repos) $null }
    function Get-CIPPBaselineDefinition { $script:Definitions }
    function Get-CIPPAzDataTableEntity {
        param($Filter, $Table)
        switch ("$Table") {
            'BaselineRollouts' { return $script:RolloutRow }
            'CommunityRepos' { return @() }
            'Baselines' { return $script:DeltaRows }
            'BaselineRolloutState' { return @() }
        }
        @()
    }

    . (Join-Path $script:RepoRoot 'Modules/CIPPCore/Public/Baselines/Get-CIPPBaseline.ps1')

    $DefinitionRoot = Join-Path $script:RepoRoot 'Config/BaselineStandards'
    $script:Definitions = Get-ChildItem -Path $DefinitionRoot -Recurse -Filter '*.json' | ForEach-Object { Get-Content $_.FullName -Raw | ConvertFrom-Json }

    # The same suffix convention the migration mints, so read-upgrade keys converge with it.
    function Get-InstanceSuffix {
        param($Seed)
        $Hash = [System.Security.Cryptography.SHA256]::HashData([System.Text.Encoding]::UTF8.GetBytes("$Seed"))
        ([System.Convert]::ToHexString($Hash)).Substring(0, 8).ToLower()
    }

    function New-DeltaRow {
        param($StandardName, $Stage, $Variables, $RemediateEnabled = $false)
        [PSCustomObject]@{
            PartitionKey     = 'standardItem'
            RowKey           = ('allTenants-{0}-s{1}-b1' -f ($StandardName -replace '#', '~'), $Stage)
            standardName     = $StandardName
            templateId       = 'b1'
            scope            = 'allTenants'
            scopeId          = 'AllTenants'
            scopeName        = 'AllTenants'
            stage            = $Stage
            expectedValue    = [string](ConvertTo-Json -Compress -Depth 20 -InputObject $Variables)
            remediateEnabled = $RemediateEnabled
            alertEnabled     = $true
            alertOnRemediate = $false
        }
    }

    $script:RolloutRow = [PSCustomObject]@{
        PartitionKey = 'rollout'
        RowKey       = 'b1'
        templateName = 'Baseline'
        description  = ''
        Stages       = (ConvertTo-Json -Compress -Depth 10 -InputObject @(
                [PSCustomObject]@{ name = 'Stage 1'; logic = 'and'; conditions = @() },
                [PSCustomObject]@{ name = 'Stage 2'; logic = 'and'; conditions = @() }
            ))
        updatedAt    = 100
        updatedBy    = 'tester'
    }
}

Describe 'Get-CIPPBaseline legacy multi-select fan-out' {
    It 'fans a legacy AppDeploy template-mode row out to one instance per template' {
        $script:DeltaRows = @(
            (New-DeltaRow 'AppDeploy' 1 ([PSCustomObject]@{
                    mode        = 'template'
                    templateIds = @([PSCustomObject]@{ label = 'App A'; value = 'tpl-a' }, 'tpl-b')
                }))
        )

        $Baseline = @(Get-CIPPBaseline -ID 'b1')[0]
        $Configs = @($Baseline.stages[0].standardsConfig)

        $Configs.Count | Should -Be 2
        @($Configs.instance) | Should -Be @(('AppDeploy#m{0}' -f (Get-InstanceSuffix 'tpl-a')), ('AppDeploy#m{0}' -f (Get-InstanceSuffix 'tpl-b')))
        @($Configs.variables.templateIds) | Should -Be @('tpl-a', 'tpl-b')
        $Configs | ForEach-Object { $_.variables.mode | Should -BeExactly 'template' }
        @($Baseline.stages[0].standards) | Should -Be @($Configs.instance)
    }

    It 'keeps a copy-mode row (no identity selection) untouched' {
        $script:DeltaRows = @(
            (New-DeltaRow 'AppDeploy' 1 ([PSCustomObject]@{ mode = 'copy'; appids = 'id-1,id-2' }))
        )

        $Baseline = @(Get-CIPPBaseline -ID 'b1')[0]
        $Configs = @($Baseline.stages[0].standardsConfig)

        $Configs.Count | Should -Be 1
        $Configs[0].instance | Should -BeExactly 'AppDeploy'
        $Configs[0].variables.appids | Should -BeExactly 'id-1,id-2'
    }

    It 'lets a row that already owns an instance key win over a fanned-out duplicate' {
        $EditedKey = 'AppDeploy#m{0}' -f (Get-InstanceSuffix 'tpl-a')
        $script:DeltaRows = @(
            (New-DeltaRow 'AppDeploy' 1 ([PSCustomObject]@{ mode = 'template'; templateIds = @('tpl-a', 'tpl-b') })),
            (New-DeltaRow $EditedKey 1 ([PSCustomObject]@{ mode = 'template'; templateIds = 'tpl-a'; edited = $true }) $true)
        )

        $Baseline = @(Get-CIPPBaseline -ID 'b1')[0]
        $Configs = @($Baseline.stages[0].standardsConfig)

        $Configs.Count | Should -Be 2
        $Winner = $Configs | Where-Object { $_.instance -eq $EditedKey }
        $Winner.variables.edited | Should -BeTrue
        $Winner.remediateEnabled | Should -BeTrue
        ($Configs | Where-Object { $_.instance -ne $EditedKey }).variables.templateIds | Should -BeExactly 'tpl-b'
    }

    It 'leaves already-upgraded and unrelated rows alone, per stage' {
        $script:DeltaRows = @(
            (New-DeltaRow ('AppDeploy#m{0}' -f (Get-InstanceSuffix 'tpl-a')) 1 ([PSCustomObject]@{ mode = 'template'; templateIds = 'tpl-a' })),
            (New-DeltaRow 'AuditLog' 1 ([PSCustomObject]@{})),
            (New-DeltaRow 'AppDeploy' 2 ([PSCustomObject]@{ mode = 'template'; templateIds = @('tpl-c') }))
        )

        $Baseline = @(Get-CIPPBaseline -ID 'b1')[0]

        @($Baseline.stages[0].standardsConfig).Count | Should -Be 2
        @($Baseline.stages[0].standardsConfig.instance) | Should -Contain 'AuditLog'
        $StageTwo = @($Baseline.stages[1].standardsConfig)
        $StageTwo.Count | Should -Be 1
        $StageTwo[0].instance | Should -BeExactly ('AppDeploy#m{0}' -f (Get-InstanceSuffix 'tpl-c'))
        $StageTwo[0].variables.templateIds | Should -BeExactly 'tpl-c'
    }
}
