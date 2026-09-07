# Pins the storage contract for a multi-entry tenant selection on a scheduled task.
#
# The selection is stored verbatim for Start-UserTasksOrchestrator to expand, and
# TenantSelectionVersion marks excludedTenants as the operator's own picks rather than the snapshot
# older rows carry. It must land in the single task write - the selection used to be added by a
# second table call afterwards, so a failure there left an alert scoped to every tenant.

BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
    $FunctionPath = Join-Path $RepoRoot 'Modules/CIPPCore/Public/Add-CIPPScheduledTask.ps1'

    # Stubs so Mock has commands to replace.
    function Get-CIPPTable { param($TableName) }
    function Get-CIPPAzDataTableEntity { param($Context, $Filter, $Property) }
    function Add-CIPPAzDataTableEntity { param($Context, $Entity, [switch]$Force) }
    function Update-AzDataTableEntity { param($Context, $Entity, [switch]$Force) }
    function Add-CippQueueMessage { param($Cmdlet, $Parameters) }
    function Get-CIPPSchedulerBlockedCommands { @() }
    function Get-NormalizedError { param($Message) $Message }
    function Write-LogMessage { param($headers, $API, $message, $Sev, $tenant, $tenantid, $LogData) }
    function New-CIPPTaskDeltaQuery { param($Trigger, $TenantFilter, $PartitionKey) }

    . $FunctionPath

    function New-FakeCommand {
        param([string]$Module = 'CIPPCore', [string[]]$ParamNames)
        $params = @{}
        foreach ($p in $ParamNames) { $params[$p] = [pscustomobject]@{ Name = $p } }
        [pscustomobject]@{ Module = $Module; Parameters = $params }
    }

    function New-SelectionTask {
        param($Tenants)
        $Task = [pscustomobject]@{
            Name         = 'Scripted alert fixture'
            Command      = 'Get-CIPPAlertFixture'
            TenantFilter = [pscustomobject]@{ value = 'AllTenants'; label = '*All Tenants'; type = 'Tenant' }
            Parameters   = [pscustomobject]@{ Threshold = 5 }
        }
        if ($Tenants) { $Task | Add-Member -MemberType NoteProperty -Name 'Tenants' -Value $Tenants }
        $Task
    }
}

Describe 'Add-CIPPScheduledTask tenant selection storage' {
    BeforeEach {
        $script:Persisted = [System.Collections.Generic.List[object]]::new()
        Mock -CommandName Get-CIPPTable -MockWith { @{ Context = 'stub' } }
        Mock -CommandName Get-CIPPAzDataTableEntity -MockWith { $null }
        Mock -CommandName Add-CIPPAzDataTableEntity -MockWith { $script:Persisted.Add($Entity) }
        Mock -CommandName Update-AzDataTableEntity -MockWith { }
        Mock -CommandName Add-CippQueueMessage -MockWith { }
        Mock -CommandName Write-LogMessage -MockWith { }
        Mock -CommandName Get-Command -MockWith {
            New-FakeCommand -ParamNames @('TenantFilter', 'Threshold')
        }
    }

    It 'persists the selection and the version marker in the same entity as the task' {
        $Selection = @(
            [pscustomobject]@{ value = 'group-1'; label = 'Group 1'; type = 'Group' }
            [pscustomobject]@{ value = 'group-2'; label = 'Group 2'; type = 'Group' }
        )

        Add-CIPPScheduledTask -Task (New-SelectionTask -Tenants $Selection)

        $script:Persisted | Should -HaveCount 1
        $Entity = $script:Persisted[0]
        $Entity.TenantSelectionVersion | Should -Be 2
        $Entity.Tenant | Should -Be 'AllTenants'

        $Stored = @($Entity.Tenants | ConvertFrom-Json)
        $Stored | Should -HaveCount 2
        $Stored.value | Should -Contain 'group-1'
        $Stored.value | Should -Contain 'group-2'
    }

    It 'leaves an already-serialized selection alone so a restored backup is not double-encoded' {
        $Json = '[{"value":"group-1","label":"Group 1","type":"Group"}]'

        Add-CIPPScheduledTask -Task (New-SelectionTask -Tenants $Json)

        $script:Persisted[0].Tenants | Should -Be $Json
    }

    It 'writes no selection or marker for a single-tenant task' {
        # The entity write is a replace, so omitting both clears them when an alert is edited down
        # to one tenant.
        Add-CIPPScheduledTask -Task (New-SelectionTask)

        $Entity = $script:Persisted[0]
        $Entity.ContainsKey('Tenants') | Should -BeFalse
        $Entity.ContainsKey('TenantSelectionVersion') | Should -BeFalse
    }
}
