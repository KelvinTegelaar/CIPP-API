# Pester tests for Get-CIPPBaselineAlignment -ByStandard, including the -BaselineId / -Stage filter.

BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
    $BaselinesPath = Join-Path $RepoRoot 'Modules/CIPPCore/Public/Baselines'
    function Get-CippTable { param($tablename) @{ TableName = $tablename } }
    function Get-CIPPAzDataTableEntity { param($TableName, $Filter, $First, $Property) }
    function ConvertTo-CIPPODataFilterValue { param($Value) "$Value" }
    function Get-CIPPBaselineDefinition { }
    function Get-CIPPBaseline { param($ID) }
    . (Join-Path $BaselinesPath 'Get-CIPPBaselineAlignment.ps1')
    . (Join-Path $BaselinesPath 'Get-CIPPBaselineStageStandards.ps1')
    . (Join-Path $BaselinesPath 'Convert-CIPPBaselineResolvedEntity.ps1')
    . (Join-Path $BaselinesPath 'Expand-CIPPBaselineTemplatePackage.ps1')

    $script:PackageMember = 'IntuneTemplate#ppk-abcdef12'
    $NewStage = {
        param($Name, [object[]]$Configs)
        [pscustomobject]@{ name = $Name; standards = @($Configs.instance); standardsConfig = @($Configs) }
    }
    $Config = { param($Standard, $Instance, $Variables) [pscustomobject]@{ standard = $Standard; instance = $Instance; variables = $Variables ?? [pscustomobject]@{} } }
    $script:Baselines = @(
        [pscustomobject]@{
            GUID            = 'baseline-a'
            templateName    = 'Baseline A'
            excludedTenants = @()
            stages          = @(
                (& $NewStage 'Pilot' @(
                        (& $Config 'DisableGuests' 'DisableGuests'),
                        (& $Config 'IntuneTemplatePackage' 'IntuneTemplatePackage#pk' ([pscustomobject]@{ intuneTemplatePackage = 'Pkg' }))
                    )),
                (& $NewStage 'Broad' @((& $Config 'AuditLog' 'AuditLog')))
            )
            tenantStates    = @(
                [pscustomobject]@{ tenantFilter = 't1.com'; currentStage = 2 }
                [pscustomobject]@{ tenantFilter = 't2.com'; currentStage = 1 }
            )
        }
        [pscustomobject]@{
            GUID            = 'baseline-b'
            templateName    = 'Baseline B'
            excludedTenants = @()
            stages          = @((& $NewStage 'Only' @((& $Config 'DisableGuests' 'DisableGuests'), (& $Config 'SharedOnlyB' 'SharedOnlyB'))))
            tenantStates    = @(
                [pscustomobject]@{ tenantFilter = 't2.com'; currentStage = 1 }
                [pscustomobject]@{ tenantFilter = 't3.com'; currentStage = 1 }
            )
        }
    )
    $Row = { param($Tenant, $Standard, $Status) [pscustomobject]@{ PartitionKey = $Tenant; StandardName = $Standard; Status = $Status } }
    $script:Entities = @(
        (& $Row 't1.com' 'DisableGuests' 'Compliant')
        (& $Row 't1.com' 'AuditLog' 'Drift')
        (& $Row 't1.com' $script:PackageMember 'Compliant')
        (& $Row 't1.com' 'NotInAnyBaseline' 'Compliant')
        (& $Row 't2.com' 'DisableGuests' 'Drift')
        (& $Row 't2.com' 'AuditLog' 'Compliant')
        (& $Row 't2.com' 'SharedOnlyB' 'Compliant')
        (& $Row 't3.com' 'DisableGuests' 'Compliant')
        (& $Row 't3.com' 'AuditLog' 'Accepted')
    )

    $script:Keys = { param($Result) @($Result.standards | ForEach-Object { foreach ($R in $_.rows) { '{0}|{1}' -f $R.tenantFilter, $R.standardName } } | Sort-Object) }
}

Describe 'Get-CIPPBaselineAlignment -ByStandard' {
    BeforeEach {
        Mock Get-CIPPBaselineDefinition {
            @([pscustomobject]@{ name = 'IntuneTemplatePackage'; package = [pscustomobject]@{ memberStandard = 'IntuneTemplate'; memberVariable = 'intuneTemplate'; variable = 'intuneTemplatePackage'; templatePartition = 'IntuneTemplate' } })
        }
        Mock Get-CIPPBaseline { $script:Baselines | Where-Object { $_.GUID -eq $ID } }
        Mock Get-CIPPAzDataTableEntity {
            switch ($TableName) {
                'BaselineAlignment' { $script:Entities }
                'templates' { @([pscustomobject]@{ PartitionKey = 'IntuneTemplate'; RowKey = 'tmpl1'; GUID = 'abcdef12-0000'; Package = 'Pkg' }) }
                'BaselineTrend' {
                    if ($Filter -like "*'fleet'*") { @([pscustomobject]@{ PartitionKey = 'fleet'; RowKey = '2000-01-01'; Aligned = 50; Verified = 40 }) }
                    else { @([pscustomobject]@{ PartitionKey = 'standard_DisableGuests'; RowKey = '2000-01-01'; Aligned = 50; Verified = 40 }) }
                }
            }
        }
    }

    It 'returns the unfiltered aggregate unchanged' {
        $r = Get-CIPPBaselineAlignment -ByStandard
        @($r.PSObject.Properties.Name) | Should -Be @('fleet', 'standards', 'tenants', 'trend', 'activeDeviations')
        $r.fleet.total | Should -Be 9
        @($r.tenants).Count | Should -Be 3
        @($r.trend).Count | Should -Be 2
        @(($r.standards | Where-Object standardName -EQ 'DisableGuests').trend).Count | Should -Be 2
    }

    It "keeps only the baseline's rolled-out standards per tenant stage" {
        $r = Get-CIPPBaselineAlignment -ByStandard -BaselineId 'baseline-a'
        # t2 sits in stage 1, so it gets no stage-2 AuditLog row.
        & $script:Keys $r | Should -Be @('t1.com|AuditLog', 't1.com|DisableGuests', "t1.com|$script:PackageMember", 't2.com|DisableGuests')
        $r.fleet.total | Should -Be 4
        $r.fleet.drift | Should -Be 2
        @($r.tenants.tenantFilter | Sort-Object) | Should -Be @('t1.com', 't2.com')
        $r.filter.baselineId | Should -Be 'baseline-a'
        $r.filter.baselineName | Should -Be 'Baseline A'
        $r.filter.stage | Should -BeNullOrEmpty
    }

    It 'counts a standard shared by two baselines under both filters' {
        $a = Get-CIPPBaselineAlignment -ByStandard -BaselineId 'baseline-a'
        $b = Get-CIPPBaselineAlignment -ByStandard -BaselineId 'baseline-b'
        & $script:Keys $b | Should -Be @('t2.com|DisableGuests', 't2.com|SharedOnlyB', 't3.com|DisableGuests')
        & $script:Keys $a | Should -Contain 't2.com|DisableGuests'
        @($b.activeDeviations).Count | Should -Be 0
    }

    It 'limits to one stage for tenants that reached it' {
        $s2 = Get-CIPPBaselineAlignment -ByStandard -BaselineId 'baseline-a' -Stage 2
        & $script:Keys $s2 | Should -Be @('t1.com|AuditLog')
        $s2.filter.stage | Should -Be 2
        $s2.filter.stageName | Should -Be 'Broad'
        $s1 = Get-CIPPBaselineAlignment -ByStandard -BaselineId 'baseline-a' -Stage 1
        & $script:Keys $s1 | Should -Be @('t1.com|DisableGuests', "t1.com|$script:PackageMember", 't2.com|DisableGuests')
    }

    It "returns only today's live trend point when filtered" {
        $r = Get-CIPPBaselineAlignment -ByStandard -BaselineId 'baseline-a'
        @($r.trend).Count | Should -Be 1
        $r.trend[0].date | Should -Be (Get-Date).ToUniversalTime().ToString('yyyy-MM-dd')
        @(($r.standards | Where-Object standardName -EQ 'DisableGuests').trend).Count | Should -Be 1
        Should -Not -Invoke Get-CIPPAzDataTableEntity -ParameterFilter { $TableName -eq 'BaselineTrend' }
    }

    It 'throws for an unknown baseline or stage' {
        { Get-CIPPBaselineAlignment -ByStandard -BaselineId 'nope' } | Should -Throw "*'nope' was not found*"
        { Get-CIPPBaselineAlignment -ByStandard -BaselineId 'baseline-a' -Stage 3 } | Should -Throw '*has no stage 3*'
        { Get-CIPPBaselineAlignment -ByStandard -Stage 1 } | Should -Throw '*requires BaselineId*'
    }
}
