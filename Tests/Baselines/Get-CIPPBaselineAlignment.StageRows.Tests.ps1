# A template configured in two rolled-out stages runs once, from the later stage, so the tenant view
# must not show the earlier copy as a 'No Data' row that can never resolve.

BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
    $BaselinesPath = Join-Path $RepoRoot 'Modules/CIPPCore/Public/Baselines'
    function Get-CippTable { param($tablename) @{ TableName = $tablename } }
    function Get-CIPPAzDataTableEntity { param($TableName, $Filter, $First, $Property) }
    function ConvertTo-CIPPODataFilterValue { param($Value) "$Value" -replace "'", "''" }
    function Get-CIPPBaselineDefinition { }
    function Get-CIPPBaseline { param($ID) }
    function Get-CIPPBaselineStageStandards { param($Baseline, $Definitions) }
    function Get-CIPPTextReplacement { param($TenantFilter, $Text, [switch]$EscapeForJson) $Text }
    function Get-TenantGroups { }
    function Get-Tenants { param($TenantFilter, [switch]$IncludeErrors) @() }
    . (Join-Path $BaselinesPath 'Get-CIPPBaselineAlignment.ps1')
    . (Join-Path $BaselinesPath 'Convert-CIPPBaselineResolvedEntity.ps1')

    $Config = { param($Key, $Template) [pscustomobject]@{ instance = $Key; variables = [pscustomobject]@{ intuneTemplate = [pscustomobject]@{ value = $Template } } } }
    $script:Baseline = [pscustomobject]@{
        GUID            = 'b1'
        templateName    = 'Silver'
        assignedTenants = @('t1.com')
        excludedTenants = @()
        tenantStates    = @([pscustomobject]@{ tenantFilter = 't1.com'; tenantName = 'T1'; currentStage = 3 })
        stages          = @(
            [pscustomobject]@{ name = 'Report'; standards = @('IntuneTemplate#early', 'IntuneTemplate#solo'); standardsConfig = @((& $Config 'IntuneTemplate#early' 'tpl-a'), (& $Config 'IntuneTemplate#solo' 'tpl-b')) }
            [pscustomobject]@{ name = 'Low'; standards = @(); standardsConfig = @() }
            [pscustomobject]@{ name = 'Deploy'; standards = @('IntuneTemplate#late'); standardsConfig = @((& $Config 'IntuneTemplate#late' 'tpl-a')) }
        )
    }
}

Describe 'Get-CIPPBaselineAlignment stage No Data rows' {
    BeforeEach {
        Mock Get-CIPPBaselineDefinition { @([pscustomobject]@{ name = 'IntuneTemplate'; label = 'Intune Template'; instanceIdentity = 'intuneTemplate' }) }
        Mock Get-CIPPBaseline { @($script:Baseline) }
        Mock Get-CIPPAzDataTableEntity {
            if ($TableName -eq 'BaselineAlignment') {
                @([pscustomobject]@{ PartitionKey = 't1.com'; RowKey = 'IntuneTemplate~late'; StandardName = 'IntuneTemplate#late'; Status = 'Compliant' })
            }
        }
    }

    It 'shows a template in two stages once, from the stage the engine runs it in' {
        $Rows = @((Get-CIPPBaselineAlignment -TenantFilter 't1.com').rows)

        @($Rows.standardName | Sort-Object) | Should -Be @('IntuneTemplate#late', 'IntuneTemplate#solo')
        ($Rows | Where-Object standardName -EQ 'IntuneTemplate#solo').status | Should -Be 'No Data'
    }
}
