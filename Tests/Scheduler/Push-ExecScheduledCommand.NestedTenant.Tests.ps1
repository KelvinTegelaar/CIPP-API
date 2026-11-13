# Pester tests for tenant values nested inside stored scheduled-task parameters.
#
# Activity functions take the tenant inside an object parameter (-Item). Stored parameters are user input, so a
# tenant carried there must be forced to the task's own tenant exactly like a top-level -TenantFilter is.

BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
    $FunctionPath = Get-ChildItem -Path (Join-Path $RepoRoot 'Modules') -Recurse -Filter 'Push-ExecScheduledCommand.ps1' -File | Select-Object -First 1 -ExpandProperty FullName

    . (Join-Path $RepoRoot 'Modules/CIPPCore/Public/Get-CIPPScheduledTaskNextRun.ps1')

    function Set-CippScheduledTaskContext { param($TaskId, $AlertReNotify, $AlertRun) }
    function Set-CippUserAgentContext { param($Headers, $Source, $TaskId) }
    function Get-CippTable { param($tablename) }
    function Get-AzDataTableEntity { param($Context, $Filter) }
    function Update-AzDataTableEntity { param($Context, $Entity, [switch]$Force) }
    function Add-CIPPAzDataTableEntity { param($Context, $Entity, [switch]$Force) }
    function Get-Tenants { param($TenantFilter) }
    function Get-CIPPSchedulerBlockedCommands { @() }
    function Write-LogMessage { param($headers, $API, $message, $sev, $tenant, $tenantid, $LogData) }
    function Send-CIPPScheduledTaskAlert { param($Results, $TaskInfo, $TenantFilter, $TaskType, $Attachments) }
    function Get-CippException { param($Exception) @{ NormalizedError = "$Exception" } }

    $script:Received = $null
    $Record = { param($Item, $Requests) $script:Received = @{ Item = $Item; Requests = $Requests } }
    $null = New-Module -Name CIPPActivityTriggers -ArgumentList $Record -ScriptBlock {
        param($Record)
        function Push-CIPPItemWorker {
            [CmdletBinding()]
            param($Item, $Requests)
            & $Record $Item $Requests
            return 'ok'
        }
    } | Import-Module -Force -PassThru

    . $FunctionPath

    function Invoke-Task {
        param([hashtable]$Parameters, [string]$Tenant = 'authorized.onmicrosoft.com')
        Push-ExecScheduledCommand -Item ([pscustomobject]@{
                Command    = 'Push-CIPPItemWorker'
                Parameters = $Parameters
                TaskInfo   = [pscustomobject]@{ PartitionKey = 'ScheduledTask'; RowKey = 'task-1'; Name = 'Nested tenant task'; Tenant = $Tenant; Recurrence = '0' }
            })
    }
}

AfterAll {
    Remove-Module -Name CIPPActivityTriggers -Force -ErrorAction SilentlyContinue
}

Describe 'Push-ExecScheduledCommand forces tenants nested in parameters' {
    BeforeEach {
        $script:Received = $null
        Mock -CommandName Set-CippScheduledTaskContext -MockWith { }
        Mock -CommandName Set-CippUserAgentContext -MockWith { }
        Mock -CommandName Get-CippTable -MockWith { @{ Context = 'stub' } }
        Mock -CommandName Update-AzDataTableEntity -MockWith { }
        Mock -CommandName Add-CIPPAzDataTableEntity -MockWith { }
        Mock -CommandName Get-Tenants -MockWith { [pscustomobject]@{ customerId = '11111111-1111-1111-1111-111111111111'; defaultDomainName = 'authorized.onmicrosoft.com' } }
        Mock -CommandName Write-LogMessage -MockWith { }
        Mock -CommandName Send-CIPPScheduledTaskAlert -MockWith { }
        Mock -CommandName Get-AzDataTableEntity -MockWith { [pscustomobject]@{ PartitionKey = 'ScheduledTask'; RowKey = 'task-1'; TaskState = 'Running' } }
    }

    It 'replaces Item.<_> naming another tenant with the task tenant' -ForEach @('TenantFilter', 'Tenant', 'tenantfilter') {
        Invoke-Task -Parameters @{ Item = @{ $_ = 'victim.onmicrosoft.com'; Name = 'Domains' } }

        $script:Received.Item.$_ | Should -Be 'authorized.onmicrosoft.com'
        $script:Received.Item.Name | Should -Be 'Domains'
        Should -Invoke -CommandName Write-LogMessage -Times 1 -ParameterFilter { $sev -eq 'Error' -and $message -match 'victim\.onmicrosoft\.com' }
    }

    It 'replaces Item.<_> naming another tenant with the task tenant id' -ForEach @('TenantId', 'customerId') {
        Invoke-Task -Parameters @{ Item = @{ $_ = '99999999-9999-9999-9999-999999999999' } }

        $script:Received.Item.$_ | Should -Be '11111111-1111-1111-1111-111111111111'
    }

    It 'replaces the value of a selector-shaped tenant' {
        Invoke-Task -Parameters @{ Item = @{ TenantFilter = @{ value = 'victim.onmicrosoft.com'; label = 'Victim' } } }

        $script:Received.Item.TenantFilter.value | Should -Be 'authorized.onmicrosoft.com'
    }

    It 'reaches tenants inside arrays and deeper objects' {
        Invoke-Task -Parameters @{ Requests = @(@{ TenantFilter = 'victim.onmicrosoft.com'; Inner = @{ Tenant = 'victim2.onmicrosoft.com' } }) }

        @($script:Received.Requests)[0].TenantFilter | Should -Be 'authorized.onmicrosoft.com'
        @($script:Received.Requests)[0].Inner.Tenant | Should -Be 'authorized.onmicrosoft.com'
    }

    It 'leaves a nested tenant alone when it already is the task tenant, by <Name>' -ForEach @(
        @{ Name = 'domain'; Key = 'TenantFilter'; Value = 'authorized.onmicrosoft.com' }
        @{ Name = 'id'; Key = 'TenantFilter'; Value = '11111111-1111-1111-1111-111111111111' }
        @{ Name = 'id under customerId'; Key = 'customerId'; Value = '11111111-1111-1111-1111-111111111111' }
    ) {
        Invoke-Task -Parameters @{ Item = @{ $Key = $Value } }

        $script:Received.Item.$Key | Should -Be $Value
        Should -Invoke -CommandName Write-LogMessage -Times 0 -ParameterFilter { $sev -eq 'Error' }
    }

    It 'leaves unrelated keys alone' {
        Invoke-Task -Parameters @{ Item = @{ partnerTenantId = '22222222-2222-2222-2222-222222222222'; id = 'abc'; Roles = @('a', 'b') } }

        $script:Received.Item.partnerTenantId | Should -Be '22222222-2222-2222-2222-222222222222'
        $script:Received.Item.id | Should -Be 'abc'
        @($script:Received.Item.Roles) | Should -Be @('a', 'b')
    }

    It 'does not rewrite nested tenants for an all-tenants task' {
        Invoke-Task -Tenant 'AllTenants' -Parameters @{ Item = @{ TenantFilter = 'specific.onmicrosoft.com' } }

        $script:Received.Item.TenantFilter | Should -Be 'specific.onmicrosoft.com'
    }
}
