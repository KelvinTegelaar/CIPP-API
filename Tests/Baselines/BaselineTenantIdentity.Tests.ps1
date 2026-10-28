# Issue #941: a tenant's default domain changed, so a tenant-scoped baseline saved under the old domain
# and a group baseline expanding to the new one resolved as two tenants, and both applied. Tenant
# scopes are stored by customerId now, and every stored value reads as the current default domain.

BeforeAll {
    $script:RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))

    $script:CustomerId = '11111111-1111-1111-1111-111111111111'
    $script:Tenant = [pscustomobject]@{ customerId = $script:CustomerId; defaultDomainName = 'contoso.com'; initialDomainName = 'contoso.onmicrosoft.com'; displayName = 'Contoso' }

    function Get-CippTable { param($tablename) @{ Context = "stub-$tablename" } }
    function ConvertTo-CIPPODataFilterValue { param($Value, $Type) "$Value" }
    function Get-Tenants { param($TenantFilter, [switch]$IncludeErrors) @($script:Tenant) }
    function Get-TenantGroups { @([pscustomobject]@{ Id = 'g1'; Name = 'Baselines'; Members = @([pscustomobject]@{ defaultDomainName = 'contoso.com' }) }) }
    function Get-CIPPBaselineDefinition { @([pscustomobject]@{ name = 'TeamsGlobalMeetingPolicy' }) }
    function Expand-CIPPBaselineTemplatePackage { param($Definition, $Config, $TemplateRows) @() }
    function Write-LogMessage { param($API, $tenant, $message, $Sev, $LogData) }
    function Get-CIPPTemplateSourceUrl { param($Source, $SourcePath, $Repos) }
    function Add-CIPPAzDataTableEntity { param($Context, $Entity, [switch]$Force) $script:Written.Add($Entity) }
    function Remove-CIPPAzDataTableEntity { param($Context, $Entity, [switch]$Force) }
    function Get-CIPPAzDataTableEntity {
        param($Context, $Filter)
        switch -Wildcard ($Filter) {
            "PartitionKey eq 'rollout'*" { $script:Rollouts }
            "*templateId eq ''*" { $script:Overrides }
            "*templateId eq '*" { $script:Deltas | Where-Object { $Filter -like "*templateId eq '$($_.templateId)'*" } }
            default { $script:States | Where-Object { $Filter -like "*PartitionKey eq '$($_.PartitionKey)'*" } }
        }
    }

    . (Join-Path $script:RepoRoot 'Modules/CIPPCore/Public/GitHub/Test-CIPPRepoSource.ps1')
    . (Join-Path $script:RepoRoot 'Modules/CIPPCore/Public/Get-CIPPTenantLookup.ps1')
    . (Join-Path $script:RepoRoot 'Modules/CIPPCore/Public/Baselines/Get-CIPPBaseline.ps1')
    . (Join-Path $script:RepoRoot 'Modules/CIPPCore/Public/Baselines/Get-CIPPBaselineWorkItems.ps1')
    . (Join-Path $script:RepoRoot 'Modules/CIPPCore/Public/Baselines/New-CIPPBaseline.ps1')

    function script:New-Rollout {
        param($Id, $ExcludedTenants = '[]', $Stages = '[{"name":"Stage 1"}]')
        [pscustomobject]@{ RowKey = $Id; templateName = $Id; Stages = $Stages; excludedTenants = $ExcludedTenants; updatedAt = 1 }
    }
    function script:New-Delta {
        param($TemplateId, $Scope, $ScopeId, [bool]$AllowAnon)
        [pscustomobject]@{
            templateId = $TemplateId; scope = $Scope; scopeId = $ScopeId; scopeName = $ScopeId; stage = 1
            standardName = 'TeamsGlobalMeetingPolicy'; expectedValue = (@{ AllowAnonymousUsersToJoinMeeting = $AllowAnon } | ConvertTo-Json -Compress)
            remediateEnabled = $true; alertEnabled = $true; alertOnRemediate = $true; updatedAt = 1
        }
    }
}

Describe 'Baseline tenant identity (#941)' {
    BeforeEach {
        $script:Overrides = @()
        $script:States = @()
        $script:Written = [System.Collections.Generic.List[object]]::new()
    }

    It 'lets a tenant baseline saved under <ScopeId> win over the group baseline' -ForEach @(
        @{ ScopeId = 'contoso.onmicrosoft.com' }
        @{ ScopeId = '11111111-1111-1111-1111-111111111111' }
    ) {
        $script:Rollouts = @((New-Rollout 'b-group'), (New-Rollout 'b-tenant'))
        $script:Deltas = @((New-Delta 'b-group' 'group' 'g1' $false), (New-Delta 'b-tenant' 'tenant' $ScopeId $true))

        $Items = @(Get-CIPPBaselineWorkItems)

        $Items.Count | Should -Be 1
        $Items[0].TenantFilter | Should -Be 'contoso.com'
        $Items[0].TemplateName | Should -Be 'b-tenant'
        $Items[0].Variables.AllowAnonymousUsersToJoinMeeting | Should -BeTrue
    }

    It 'keeps a tenant excluded by its old domain excluded' {
        $script:Rollouts = @((New-Rollout 'b-group' -ExcludedTenants '["contoso.onmicrosoft.com"]'))
        $script:Deltas = @((New-Delta 'b-group' 'group' 'g1' $false))

        @(Get-CIPPBaselineWorkItems).Count | Should -Be 0
    }

    It 'applies an ad-hoc override stored by customerId to the current domain' {
        $script:Rollouts = @((New-Rollout 'b-group'))
        $script:Deltas = @((New-Delta 'b-group' 'group' 'g1' $false))
        $script:Overrides = @((New-Delta '' 'tenant' $script:CustomerId $true))

        $Items = @(Get-CIPPBaselineWorkItems)

        $Items.Count | Should -Be 1
        $Items[0].TenantFilter | Should -Be 'contoso.com'
        $Items[0].TemplateName | Should -Be 'Tenant Override'
    }

    It 'names a renamed group by its current name, so the assignment still matches it' {
        $Rollout = New-Rollout 'b-renamed'
        $Rollout | Add-Member -NotePropertyName assignedTo -NotePropertyValue '[{"label":"Baselines (Onboarding)","value":"g1","type":"Group"}]'
        $script:Rollouts = @($Rollout)
        $Delta = New-Delta 'b-renamed' 'group' 'g1' $false
        $Delta.scopeName = 'Baselines (Onboarding)'
        $script:Deltas = @($Delta)

        $Baseline = Get-CIPPBaseline -ID 'b-renamed'

        $Baseline.assignedTenants | Should -Be @('Baselines')
        @($Baseline.assignments)[0].label | Should -Be 'Baselines'
    }

    It 'keeps the saved name of a group that no longer exists' {
        $script:Rollouts = @((New-Rollout 'b-gone'))
        $Delta = New-Delta 'b-gone' 'group' 'deleted-group' $false
        $Delta.scopeName = 'Old group'
        $script:Deltas = @($Delta)

        (Get-CIPPBaseline -ID 'b-gone').assignedTenants | Should -Be @('Old group')
    }

    It 'reads one stage per tenant and prefers the customerId row over a legacy domain row' {
        $script:Rollouts = @((New-Rollout 'b-staged' -Stages '[{"name":"One"},{"name":"Two"},{"name":"Three"}]'))
        $script:Deltas = @((New-Delta 'b-staged' 'group' 'g1' $false))
        $script:States = @(
            [pscustomobject]@{ PartitionKey = 'b-staged'; RowKey = 'contoso.onmicrosoft.com'; currentStage = 2 }
            [pscustomobject]@{ PartitionKey = 'b-staged'; RowKey = $script:CustomerId; currentStage = 3 }
        )

        $States = @((Get-CIPPBaseline -ID 'b-staged').tenantStates)

        $States.Count | Should -Be 1
        $States[0].tenantFilter | Should -Be 'contoso.com'
        $States[0].currentStage | Should -Be 3
        $States[0].customerId | Should -Be $script:CustomerId
    }

    It 'stores tenant assignments and exclusions by customerId' {
        $script:Rollouts = @()
        $Baseline = [pscustomobject]@{
            templateName    = 'Saved'
            stages          = @([pscustomobject]@{ name = 'Stage 1'; standards = @([pscustomobject]@{ standard = 'TeamsGlobalMeetingPolicy'; variables = @{} }) })
            assignedTenants = @([pscustomobject]@{ label = 'Contoso'; value = 'contoso.com'; type = 'Tenant' }, [pscustomobject]@{ label = 'Baselines'; value = 'g1'; type = 'Group' })
            excludedTenants = @([pscustomobject]@{ label = 'Contoso'; value = 'contoso.onmicrosoft.com'; type = 'Tenant' })
        }

        $null = New-CIPPBaseline -Baseline $Baseline -User 'tester'

        $Deltas = @($script:Written | Where-Object { $_.PartitionKey -eq 'standardItem' })
        ($Deltas | Where-Object { $_.scope -eq 'tenant' }).scopeId | Should -Be $script:CustomerId
        ($Deltas | Where-Object { $_.scope -eq 'group' }).scopeId | Should -Be 'g1'
        ($script:Written | Where-Object { $_.PartitionKey -eq 'rollout' }).excludedTenants | Should -Be "[`"$script:CustomerId`"]"
    }
}
