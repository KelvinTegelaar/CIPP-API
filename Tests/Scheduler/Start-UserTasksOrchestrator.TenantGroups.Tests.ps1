# Regression tests for scripted-alert tenant scope.
#
# Groups used to be expanded at save time, with the complement of the selection frozen into
# excludedTenants, so a tenant joining a targeted group afterwards never received the alert. Scope is
# now resolved here on every run from the verbatim Tenants selection. Rows written by the old code
# lack TenantSelectionVersion; their excludedTenants is that snapshot and is ignored, while
# excludedTenantGroups was never part of it and always applies.

BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
    $FunctionPath = Get-ChildItem -Path (Join-Path $RepoRoot 'Modules') -Recurse -Filter 'Start-UserTasksOrchestrator.ps1' -File -ErrorAction SilentlyContinue |
        Select-Object -First 1 -ExpandProperty FullName
    if (-not $FunctionPath) { throw 'Could not locate Start-UserTasksOrchestrator.ps1 under Modules/' }

    # Stubs so Mock has commands to replace.
    function Get-CippTable { param($tablename) }
    function Get-CIPPAzDataTableEntity { param($Context, $Filter, $Property) }
    function Update-AzDataTableEntity { param($Context, $Entity, [switch]$Force) }
    function Get-Tenants { param($TenantFilter, [switch]$IncludeErrors) }
    function Get-CIPPSchedulerBlockedCommands { @() }
    function Expand-CIPPTenantGroups { param($TenantFilter) }
    function New-CippQueueEntry { param($Name, $Reference, $TotalTasks) }
    function Start-CIPPOrchestrator { param($InputObject) }
    function Get-CIPPScheduledTaskNextRun { param($Recurrence, $ScheduledTime) }
    # Parameter names bind case-insensitively, so one $Sev covers the SUT's -Sev and -sev calls.
    function Write-LogMessage { param($headers, $API, $message, $Sev, $tenant, $tenantid, $LogData) }

    # A real function, so the SUT's Get-Command lookup resolves without mocking Pester's own
    # Get-Command. It declares TenantFilter, which is what drives the per-tenant parameter stamping.
    function Get-CIPPAlertFixture { param($TenantFilter, $Threshold) }

    . $FunctionPath

    # Four managed tenants; group-1 holds a + b, group-2 holds c, group-excluded holds c.
    function New-TenantList {
        @(
            [pscustomobject]@{ defaultDomainName = 'a.onmicrosoft.com'; customerId = 'cust-a'; displayName = 'A' }
            [pscustomobject]@{ defaultDomainName = 'b.onmicrosoft.com'; customerId = 'cust-b'; displayName = 'B' }
            [pscustomobject]@{ defaultDomainName = 'c.onmicrosoft.com'; customerId = 'cust-c'; displayName = 'C' }
            [pscustomobject]@{ defaultDomainName = 'd.onmicrosoft.com'; customerId = 'cust-d'; displayName = 'D' }
        )
    }

    function New-TaskRow {
        param([hashtable]$Overrides = @{})
        $Row = @{
            PartitionKey  = 'ScheduledTask'
            RowKey        = 'task-1'
            Name          = 'Scripted alert fixture'
            Command       = 'Get-CIPPAlertFixture'
            Parameters    = '{}'
            ScheduledTime = 1
            TaskState     = 'Planned'
            Recurrence    = '0'
            Tenant        = 'AllTenants'
            ETag          = 'etag-1'
        }
        foreach ($Key in $Overrides.Keys) { $Row[$Key] = $Overrides[$Key] }
        [pscustomobject]$Row
    }

    # The tenant each fanned-out command was stamped with, in batch order.
    function Get-ScopedTenants {
        @($script:StartedBatches | ForEach-Object { $_.Parameters.TenantFilter })
    }

    # The two groups a multi-select alert stores verbatim.
    $script:TwoGroupSelection = ConvertTo-Json -Compress -Depth 5 -InputObject @(
        [pscustomobject]@{ value = 'group-1'; label = 'Group 1'; type = 'Group' }
        [pscustomobject]@{ value = 'group-2'; label = 'Group 2'; type = 'Group' }
    )
}

Describe 'Start-UserTasksOrchestrator tenant scope resolution' {
    BeforeEach {
        $script:StartedBatches = [System.Collections.Generic.List[object]]::new()
        $script:LoggedMessages = [System.Collections.Generic.List[string]]::new()
        $script:TaskUpdates = [System.Collections.Generic.List[object]]::new()

        Mock -CommandName Get-CippTable -MockWith { @{ Context = 'stub' } }
        Mock -CommandName Update-AzDataTableEntity -MockWith { $script:TaskUpdates.Add($Entity) }
        Mock -CommandName Get-CIPPScheduledTaskNextRun -MockWith { 0 }
        Mock -CommandName Get-CIPPSchedulerBlockedCommands -MockWith { @() }
        Mock -CommandName New-CippQueueEntry -MockWith { [pscustomobject]@{ RowKey = 'queue-1' } }
        Mock -CommandName Get-Tenants -MockWith { New-TenantList }
        Mock -CommandName Write-LogMessage -MockWith {
            $script:LoggedMessages.Add([string]$message)
        }
        Mock -CommandName Start-CIPPOrchestrator -MockWith {
            foreach ($Item in @($InputObject.Batch)) { $script:StartedBatches.Add($Item) }
        }
        # Mirrors the real helper: group entries expand to their members, everything else - the
        # AllTenants sentinel included - passes through untouched.
        Mock -CommandName Expand-CIPPTenantGroups -MockWith {
            foreach ($Entry in @($TenantFilter)) {
                switch ($Entry.value) {
                    'group-1' {
                        [pscustomobject]@{ value = 'a.onmicrosoft.com'; type = 'Tenant' }
                        [pscustomobject]@{ value = 'b.onmicrosoft.com'; type = 'Tenant' }
                    }
                    'group-2' { [pscustomobject]@{ value = 'c.onmicrosoft.com'; type = 'Tenant' } }
                    'group-excluded' { [pscustomobject]@{ value = 'c.onmicrosoft.com'; type = 'Tenant' } }
                    'group-empty' { }
                    default { $Entry }
                }
            }
        }
    }

    It 'includes a group member that a legacy snapshot still lists as excluded' {
        # The reported bug: b joined group-1 after the alert was saved, so it sits in the frozen
        # complement. Without TenantSelectionVersion that column is a snapshot and must not apply.
        Mock -CommandName Get-CIPPAzDataTableEntity -MockWith {
            New-TaskRow @{
                Tenants         = $script:TwoGroupSelection
                excludedTenants = 'b.onmicrosoft.com,d.onmicrosoft.com'
            }
        }

        Start-UserTasksOrchestrator

        $Scoped = Get-ScopedTenants
        $Scoped | Should -Contain 'b.onmicrosoft.com'
        $Scoped | Should -Contain 'a.onmicrosoft.com'
        $Scoped | Should -Contain 'c.onmicrosoft.com'
        # d is in neither group, so it is out of scope on the selection alone.
        $Scoped | Should -Not -Contain 'd.onmicrosoft.com'
    }

    It 'logs only the snapshot exclusions that were actually in scope' {
        # b is in group-1 and was being wrongly excluded; d is in neither group, so dropping it from
        # the snapshot changes nothing and is not worth reporting.
        Mock -CommandName Get-CIPPAzDataTableEntity -MockWith {
            New-TaskRow @{
                Tenants         = $script:TwoGroupSelection
                excludedTenants = 'b.onmicrosoft.com,d.onmicrosoft.com'
            }
        }

        Start-UserTasksOrchestrator

        ($script:LoggedMessages -join "`n") | Should -Match 'ignored 1 stale snapshot exclusions'
    }

    It 'stays quiet when a legacy snapshot would not have changed the outcome' {
        # Otherwise every legacy row logs the same no-op on every run, forever.
        Mock -CommandName Get-CIPPAzDataTableEntity -MockWith {
            New-TaskRow @{
                Tenants         = $script:TwoGroupSelection
                excludedTenants = 'd.onmicrosoft.com'
            }
        }

        Start-UserTasksOrchestrator

        ($script:LoggedMessages -join "`n") | Should -Not -Match 'stale snapshot exclusions'
    }

    It 'applies excludedTenants on a versioned row' {
        # Written by the current code, so the column holds only the operator's own picks.
        Mock -CommandName Get-CIPPAzDataTableEntity -MockWith {
            New-TaskRow @{
                Tenants                = $script:TwoGroupSelection
                TenantSelectionVersion = 2
                excludedTenants        = 'b.onmicrosoft.com'
            }
        }

        Start-UserTasksOrchestrator

        $Scoped = Get-ScopedTenants
        $Scoped | Should -Not -Contain 'b.onmicrosoft.com'
        $Scoped | Should -Contain 'a.onmicrosoft.com'
        $Scoped | Should -Contain 'c.onmicrosoft.com'
    }

    It 'expands excludedTenantGroups on a legacy row, since it was never part of the snapshot' {
        Mock -CommandName Get-CIPPAzDataTableEntity -MockWith {
            New-TaskRow @{
                Tenants              = $script:TwoGroupSelection
                excludedTenants      = 'b.onmicrosoft.com'
                excludedTenantGroups = (ConvertTo-Json -Compress -Depth 5 -InputObject @(
                        [pscustomobject]@{ value = 'group-excluded'; label = 'Excluded'; type = 'Group' }))
            }
        }

        Start-UserTasksOrchestrator

        $Scoped = Get-ScopedTenants
        # c is excluded via the group; b is not, because the snapshot column is ignored.
        $Scoped | Should -Not -Contain 'c.onmicrosoft.com'
        $Scoped | Should -Contain 'b.onmicrosoft.com'
    }

    It 'fans out to every tenant when the selection carries the AllTenants sentinel' {
        Mock -CommandName Get-CIPPAzDataTableEntity -MockWith {
            New-TaskRow @{
                Tenants                = (ConvertTo-Json -Compress -Depth 5 -InputObject @(
                        [pscustomobject]@{ value = 'AllTenants'; label = '*All Tenants'; type = 'Tenant' }
                        [pscustomobject]@{ value = 'group-1'; label = 'Group 1'; type = 'Group' }))
                TenantSelectionVersion = 2
            }
        }

        Start-UserTasksOrchestrator

        Get-ScopedTenants | Should -HaveCount 4
    }

    It 'still resolves a single stored group when no Tenants column is present' {
        Mock -CommandName Get-CIPPAzDataTableEntity -MockWith {
            New-TaskRow @{
                Tenant      = 'group-1'
                TenantGroup = '{"value":"group-1","label":"Group 1","type":"Group"}'
            }
        }

        Start-UserTasksOrchestrator

        $Scoped = Get-ScopedTenants
        $Scoped | Should -HaveCount 2
        $Scoped | Should -Contain 'a.onmicrosoft.com'
        $Scoped | Should -Contain 'b.onmicrosoft.com'
    }

    It 'keeps operator exclusions on a legacy selection that includes AllTenants' {
        # The old save path skipped the complement when the selection carried the sentinel, so these
        # exclusions are the operator's own and must survive despite the missing version marker.
        Mock -CommandName Get-CIPPAzDataTableEntity -MockWith {
            New-TaskRow @{
                Tenants         = (ConvertTo-Json -Compress -Depth 5 -InputObject @(
                        [pscustomobject]@{ value = 'AllTenants'; label = '*All Tenants'; type = 'Tenant' }
                        [pscustomobject]@{ value = 'group-1'; label = 'Group 1'; type = 'Group' }))
                excludedTenants = 'b.onmicrosoft.com'
            }
        }

        Start-UserTasksOrchestrator

        $Scoped = Get-ScopedTenants
        $Scoped | Should -HaveCount 3
        $Scoped | Should -Not -Contain 'b.onmicrosoft.com'
    }

    It 'fails the task rather than queuing an AllTenants run when expansion throws' {
        Mock -CommandName Get-CIPPAzDataTableEntity -MockWith {
            New-TaskRow @{ Tenants = $script:TwoGroupSelection; TenantSelectionVersion = 2 }
        }
        Mock -CommandName Expand-CIPPTenantGroups -MockWith { throw 'tenant group store unavailable' }

        Start-UserTasksOrchestrator

        Get-ScopedTenants | Should -HaveCount 0
        $Failed = @($script:TaskUpdates | Where-Object { $_.TaskState -eq 'Failed' })
        $Failed | Should -HaveCount 1
        $Failed[0].Results | Should -Match 'Failed to expand tenant selection'
    }

    It 'keeps a recurring task alive when expansion throws' {
        # Failed is terminal, so parking a recurring task there on a transient table read would stop
        # it permanently.
        Mock -CommandName Get-CIPPAzDataTableEntity -MockWith {
            New-TaskRow @{ Tenants = $script:TwoGroupSelection; TenantSelectionVersion = 2; Recurrence = '1d' }
        }
        Mock -CommandName Expand-CIPPTenantGroups -MockWith { throw 'tenant group store unavailable' }
        Mock -CommandName Get-CIPPScheduledTaskNextRun -MockWith { 1700000000 }

        Start-UserTasksOrchestrator

        $Failed = @($script:TaskUpdates | Where-Object { $_.TaskState -like 'Failed*' })
        $Failed | Should -HaveCount 1
        $Failed[0].TaskState | Should -Be 'Failed - Planned'
        $Failed[0].ScheduledTime | Should -Be '1700000000'
    }

    It 'ignores a stored selection on a row the execution gates read as single-tenant' {
        # Tenant is not the AllTenants literal, so Push-ExecScheduledCommand would treat any fan-out
        # here as a single-tenant run: no per-tenant results, and concurrent parent-row writes.
        Mock -CommandName Get-CIPPAzDataTableEntity -MockWith {
            New-TaskRow @{ Tenant = 'a.onmicrosoft.com'; Tenants = $script:TwoGroupSelection }
        }

        Start-UserTasksOrchestrator

        $Scoped = Get-ScopedTenants
        $Scoped | Should -HaveCount 1
        $Scoped | Should -Contain 'a.onmicrosoft.com'
    }

    It 'reschedules a recurring task whose groups all resolved empty' {
        # Otherwise the row stays Pending, is reclaimed as stale every hour, and never advances.
        Mock -CommandName Get-CIPPAzDataTableEntity -MockWith {
            New-TaskRow @{
                Tenants                = (ConvertTo-Json -Compress -Depth 5 -InputObject @(
                        [pscustomobject]@{ value = 'group-empty'; label = 'Empty'; type = 'Group' }))
                TenantSelectionVersion = 2
                Recurrence             = '1d'
            }
        }
        Mock -CommandName Get-CIPPScheduledTaskNextRun -MockWith { 1700000000 }

        Start-UserTasksOrchestrator

        Get-ScopedTenants | Should -HaveCount 0
        $Closed = @($script:TaskUpdates | Where-Object { $_.Results -eq 'No tenants in scope for this task.' })
        $Closed | Should -HaveCount 1
        $Closed[0].TaskState | Should -Be 'Planned'
        $Closed[0].ScheduledTime | Should -Be '1700000000'
    }

    It 'completes a one-off task whose groups all resolved empty' {
        Mock -CommandName Get-CIPPAzDataTableEntity -MockWith {
            New-TaskRow @{
                Tenants                = (ConvertTo-Json -Compress -Depth 5 -InputObject @(
                        [pscustomobject]@{ value = 'group-empty'; label = 'Empty'; type = 'Group' }))
                TenantSelectionVersion = 2
            }
        }

        Start-UserTasksOrchestrator

        $Closed = @($script:TaskUpdates | Where-Object { $_.Results -eq 'No tenants in scope for this task.' })
        $Closed | Should -HaveCount 1
        $Closed[0].TaskState | Should -Be 'Completed'
        $Closed[0].ContainsKey('ScheduledTime') | Should -BeFalse
    }

    It 'leaves a plain single-tenant task alone' {
        Mock -CommandName Get-CIPPAzDataTableEntity -MockWith {
            New-TaskRow @{ Tenant = 'a.onmicrosoft.com' }
        }

        Start-UserTasksOrchestrator

        $Scoped = Get-ScopedTenants
        $Scoped | Should -HaveCount 1
        $Scoped | Should -Contain 'a.onmicrosoft.com'
        Should -Invoke -CommandName Expand-CIPPTenantGroups -Times 0
    }

    It 'fans out to an AllTenants task that stored no selection' {
        Mock -CommandName Get-CIPPAzDataTableEntity -MockWith {
            New-TaskRow @{ excludedTenants = 'd.onmicrosoft.com' }
        }

        Start-UserTasksOrchestrator

        $Scoped = Get-ScopedTenants
        $Scoped | Should -HaveCount 3
        # No Tenants column means no snapshot, so the exclusion is the operator's and still applies.
        $Scoped | Should -Not -Contain 'd.onmicrosoft.com'
    }
}
