# Regression tests for the save side of scripted-alert tenant scope.
#
# This endpoint used to expand groups and store the complement of the selection in excludedTenants,
# freezing membership at save time. It now stores the selection verbatim for
# Start-UserTasksOrchestrator to expand, so nothing here may touch tenant or group state.

BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
    $FunctionPath = Get-ChildItem -Path (Join-Path $RepoRoot 'Modules') -Recurse -Filter 'Invoke-AddScriptedAlert.ps1' -File -ErrorAction SilentlyContinue |
        Select-Object -First 1 -ExpandProperty FullName
    if (-not $FunctionPath) { throw 'Could not locate Invoke-AddScriptedAlert.ps1 under Modules/' }

    # Stubs so Mock has commands to replace.
    function Invoke-AddScheduledItem { param($Request, $TriggerMetadata) }
    function Expand-CIPPTenantGroups { param($TenantFilter) }
    function Get-Tenants { param($TenantFilter, [switch]$IncludeErrors) }
    function Get-CIPPTable { param($TableName) }
    function Update-AzDataTableEntity { param($Context, $Entity, [switch]$Force) }

    . $FunctionPath

    function New-AlertRequest {
        param($TenantFilter, $ExcludedTenants)
        $Body = [pscustomobject]@{
            Name         = 'Scripted alert fixture'
            Command      = [pscustomobject]@{ value = 'Get-CIPPAlertFixture' }
            tenantFilter = $TenantFilter
        }
        if ($PSBoundParameters.ContainsKey('ExcludedTenants')) {
            $Body | Add-Member -MemberType NoteProperty -Name 'excludedTenants' -Value $ExcludedTenants
        }
        [pscustomobject]@{ Body = $Body; Headers = @{} }
    }

    $script:TwoGroups = @(
        [pscustomobject]@{ value = 'group-1'; label = 'Group 1'; type = 'Group' }
        [pscustomobject]@{ value = 'group-2'; label = 'Group 2'; type = 'Group' }
    )
}

Describe 'Invoke-AddScriptedAlert tenant selection' {
    BeforeEach {
        $script:Forwarded = $null
        Mock -CommandName Invoke-AddScheduledItem -MockWith { $script:Forwarded = $Request; 'Task added' }
        Mock -CommandName Get-CIPPTable -MockWith { @{ Context = 'stub' } }
        Mock -CommandName Update-AzDataTableEntity -MockWith { }
        Mock -CommandName Expand-CIPPTenantGroups -MockWith { throw 'groups must not be expanded at save time' }
        Mock -CommandName Get-Tenants -MockWith { throw 'the tenant list must not be read at save time' }
    }

    It 'forwards the multi-group selection verbatim' {
        Invoke-AddScriptedAlert -Request (New-AlertRequest -TenantFilter $script:TwoGroups)

        $Stored = @($script:Forwarded.Body.Tenants)
        $Stored | Should -HaveCount 2
        $Stored[0].value | Should -Be 'group-1'
        $Stored[0].type | Should -Be 'Group'
        $Stored[1].value | Should -Be 'group-2'
    }

    It 'keeps Tenant as the AllTenants literal the execution gates rely on' {
        # Push-ExecScheduledCommand and Start-UserTasksOrchestrator both decide multi-tenant
        # behaviour by comparing this column to 'AllTenants'.
        Invoke-AddScriptedAlert -Request (New-AlertRequest -TenantFilter $script:TwoGroups)

        $script:Forwarded.Body.tenantFilter.value | Should -Be 'AllTenants'
    }

    It 'never expands groups or reads the tenant list' {
        # Both mocks throw; reaching either would fail the call and leave nothing forwarded.
        Invoke-AddScriptedAlert -Request (New-AlertRequest -TenantFilter $script:TwoGroups)

        $script:Forwarded | Should -Not -BeNullOrEmpty
        Should -Invoke -CommandName Expand-CIPPTenantGroups -Times 0
        Should -Invoke -CommandName Get-Tenants -Times 0
    }

    It 'writes no complement into excludedTenants' {
        Invoke-AddScriptedAlert -Request (New-AlertRequest -TenantFilter $script:TwoGroups)

        # The property is only ever set from what the operator picked; with none picked it stays unset.
        @($script:Forwarded.Body.excludedTenants) | Where-Object { $_ } | Should -HaveCount 0
    }

    It 'passes the operator exclusions through unchanged' {
        $Excluded = @(
            [pscustomobject]@{ value = 'b.onmicrosoft.com'; label = 'B'; type = 'Tenant' }
            [pscustomobject]@{ value = 'group-excluded'; label = 'Excluded'; type = 'Group' }
        )

        Invoke-AddScriptedAlert -Request (New-AlertRequest -TenantFilter $script:TwoGroups -ExcludedTenants $Excluded)

        $Stored = @($script:Forwarded.Body.excludedTenants)
        $Stored | Should -HaveCount 2
        $Stored.value | Should -Contain 'b.onmicrosoft.com'
        ($Stored | Where-Object { $_.type -eq 'Group' }).value | Should -Be 'group-excluded'
    }

    It 'normalizes bare domain strings an API caller may post as exclusions' {
        # Add-CIPPScheduledTask drops entries without a .value, so plain strings must be wrapped.
        Invoke-AddScriptedAlert -Request (New-AlertRequest -TenantFilter $script:TwoGroups -ExcludedTenants @('b.onmicrosoft.com'))

        $Stored = @($script:Forwarded.Body.excludedTenants)
        $Stored | Should -HaveCount 1
        $Stored[0].value | Should -Be 'b.onmicrosoft.com'
        $Stored[0].type | Should -Be 'Tenant'
    }

    It 'stores no selection for a single-entry pick, leaving the existing single-tenant path' {
        $Single = @([pscustomobject]@{ value = 'group-1'; label = 'Group 1'; type = 'Group' })

        Invoke-AddScriptedAlert -Request (New-AlertRequest -TenantFilter $Single)

        $script:Forwarded.Body.Tenants | Should -BeNullOrEmpty
        $script:Forwarded.Body.tenantFilter.value | Should -Be 'group-1'
    }

    It 'does not write to the table itself' {
        # The selection rides along in the single Add-CIPPScheduledTask write. A second, separate
        # write could fail after the task was created, leaving an alert scoped to every tenant.
        Invoke-AddScriptedAlert -Request (New-AlertRequest -TenantFilter $script:TwoGroups)

        Should -Invoke -CommandName Update-AzDataTableEntity -Times 0
    }
}
