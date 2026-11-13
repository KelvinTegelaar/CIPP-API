# "Exclude onboarded tenant from All Tenant standards" puts the tenant in the 'Excluded onboarded tenants' group
# and excludes that group from every All Tenants classic standards template and baseline. The block is run on its
# own, lifted from the activity, because the steps before it need a live GDAP relationship.

BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
    $Path = Join-Path $RepoRoot 'Modules/CIPPActivityTriggers/Public/Entrypoints/Activity Triggers/Push-ExecOnboardTenantQueue.ps1'
    $Ast = [System.Management.Automation.Language.Parser]::ParseFile($Path, [ref]$null, [ref]$null)
    $If = $Ast.Find({ param($Node)
            $Node -is [System.Management.Automation.Language.IfStatementAst] -and
            $Node.Clauses[0].Item1.Extent.Text -eq '$StandardsExcludeAllTenants -eq $true' -and
            $Node.Extent.Text -match 'Excluded onboarded tenants'
        }, $true)
    $Body = $If.Clauses[0].Item2.Extent.Text
    $script:ExclusionBlock = [ScriptBlock]::Create($Body.Substring(1, $Body.Length - 2))

    function Get-CIPPTable { param($tablename) @{ TableName = $tablename } }
    function Get-TenantGroups { param([switch]$SkipCache) }
    function Add-CIPPAzDataTableEntity { param($TableName, $Entity, [switch]$Force) $script:Written.Add([pscustomobject]@{ Table = $TableName; Entity = $Entity }) }
    function Get-CIPPAzDataTableEntity {
        param($TableName, $Filter)
        switch ($TableName) {
            'TenantGroups' { @([pscustomobject]@{ PartitionKey = 'TenantGroup'; RowKey = 'g-excl'; Name = 'Excluded onboarded tenants' }) }
            'templates' { @() }
            'BaselineRollouts' { $script:Rollouts }
        }
    }

    function New-Rollout($Id, $AssignedTo, $ExcludedTo = '[]', $ExcludedTenants = '[]') {
        [pscustomobject]@{ PartitionKey = 'rollout'; RowKey = $Id; templateName = $Id; assignedTo = $AssignedTo; excludedTo = $ExcludedTo; excludedTenants = $ExcludedTenants }
    }
    function Invoke-Exclusion {
        $Tenant = [pscustomobject]@{ customerId = 'tenant-new'; defaultDomainName = 'new.com' }
        $Logs = [System.Collections.Generic.List[object]]::new()
        . $script:ExclusionBlock
    }
}

Describe 'onboarding exclusion from All Tenants baselines' {
    BeforeEach { $script:Written = [System.Collections.Generic.List[object]]::new() }

    It 'adds the group to the exclusions of a baseline assigned to All Tenants' {
        $script:Rollouts = @(New-Rollout 'b-all' '[{"label":"All Tenants","value":"AllTenants","type":"Tenant"}]' '[{"label":"Old","value":"old.com","type":"Tenant"}]' '["tenant-old"]')
        Invoke-Exclusion
        $Saved = $script:Written.Where({ $_.Table -eq 'BaselineRollouts' }).Entity
        $Saved | Should -HaveCount 1
        ($Saved.excludedTenants | ConvertFrom-Json) | Should -Be @('tenant-old', 'g-excl')
        ($Saved.excludedTo | ConvertFrom-Json).value | Should -Be @('old.com', 'g-excl')
        ($Saved.excludedTo | ConvertFrom-Json)[1].type | Should -Be 'Group'
    }

    It 'leaves a baseline alone when <Case>' -ForEach @(
        @{ Case = 'it is assigned to specific tenants'; Rollout = { New-Rollout 'b-one' '[{"value":"contoso.com","type":"Tenant"}]' } }
        @{ Case = 'it already excludes the group'; Rollout = { New-Rollout 'b-done' '[{"value":"AllTenants"}]' '[{"value":"g-excl","type":"Group"}]' '["g-excl"]' } }
    ) {
        $script:Rollouts = @(& $Rollout)
        Invoke-Exclusion
        $script:Written.Where({ $_.Table -eq 'TenantGroupMembers' }).Count | Should -Be 1
        $script:Written.Where({ $_.Table -eq 'BaselineRollouts' }).Count | Should -Be 0
    }

    It 'handles a baseline saved before the exclusion columns existed' {
        $Old = [pscustomobject]@{ PartitionKey = 'rollout'; RowKey = 'b-legacy'; templateName = 'b-legacy'; assignedTo = '["AllTenants"]' }
        $script:Rollouts = @($Old)
        Invoke-Exclusion
        $Saved = $script:Written.Where({ $_.Table -eq 'BaselineRollouts' }).Entity
        ($Saved.excludedTenants | ConvertFrom-Json) | Should -Be @('g-excl')
    }
}
