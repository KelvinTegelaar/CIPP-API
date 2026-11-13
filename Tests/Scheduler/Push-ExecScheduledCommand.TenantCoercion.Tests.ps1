# Regression tests for the scheduler tenant-authorization gap (INC-2026-003 Finding 3), execution side.
#
# Even if a stored task somehow carries a tenant-identifying parameter (legacy rows created before the
# creation-time strip, or a direct table write), Push-ExecScheduledCommand must force every tenant
# parameter the command declares to the task's own authorized tenant before invoking it. This is the
# class-closing defense: it protects every current and future cmdlet regardless of its parameter name.

BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
    $FunctionPath = Get-ChildItem -Path (Join-Path $RepoRoot 'Modules') -Recurse -Filter 'Push-ExecScheduledCommand.ps1' -File -ErrorAction SilentlyContinue |
        Select-Object -First 1 -ExpandProperty FullName
    if (-not $FunctionPath) { throw 'Could not locate Push-ExecScheduledCommand.ps1 under Modules/' }

    . (Join-Path $RepoRoot 'Modules/CIPPCore/Public/Get-CIPPScheduledTaskNextRun.ps1')

    # Stubs for the module surface Push-ExecScheduledCommand touches.
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

    # The command under test records exactly which tenant it was invoked against. It declares its own
    # -Tenant (the report-cmdlet shape that is NOT alias-renamed, so the parameter really is 'Tenant'
    # and survives the SUT's unknown-parameter strip).
    # The executor only runs functions from the CIPP modules, so it lives in a module of that name and
    # records through a script block bound to this file's scope.
    $script:InvokedWith = $null
    $Record = { param($Tenant, $AuthenticationMethodId) $script:InvokedWith = @{ Tenant = $Tenant; AuthenticationMethodId = $AuthenticationMethodId } }
    $null = New-Module -Name CIPPCore -ArgumentList $Record -ScriptBlock {
        param($Record)
        function Get-CIPPTenantScopedReport {
            [CmdletBinding()]
            param([Parameter(Mandatory = $true)]$Tenant, $AuthenticationMethodId, $Enabled)
            & $Record $Tenant $AuthenticationMethodId
            return 'ok'
        }
    } | Import-Module -Force -PassThru

    . $FunctionPath
}

AfterAll {
    Remove-Module -Name CIPPCore -Force -ErrorAction SilentlyContinue
}

Describe 'Push-ExecScheduledCommand tenant-parameter coercion' {
    BeforeEach {
        $script:InvokedWith = $null
        Mock -CommandName Set-CippScheduledTaskContext -MockWith { }
        Mock -CommandName Set-CippUserAgentContext -MockWith { }
        Mock -CommandName Get-CippTable -MockWith { @{ Context = 'stub' } }
        Mock -CommandName Update-AzDataTableEntity -MockWith { }
        Mock -CommandName Add-CIPPAzDataTableEntity -MockWith { }
        Mock -CommandName Get-Tenants -MockWith { [pscustomobject]@{ customerId = 'cust-authorized' } }
        Mock -CommandName Write-LogMessage -MockWith { }
        Mock -CommandName Send-CIPPScheduledTaskAlert -MockWith { }
        # A live, non-completed task row so execution proceeds.
        Mock -CommandName Get-AzDataTableEntity -MockWith {
            [pscustomobject]@{ PartitionKey = 'ScheduledTask'; RowKey = 'task-1'; TaskState = 'Running' }
        }
        $script:BaseItem = @{
            Command  = 'Get-CIPPTenantScopedReport'
            TaskInfo = [pscustomobject]@{
                PartitionKey = 'ScheduledTask'
                RowKey       = 'task-1'
                Name         = 'Auth policy task'
                Tenant       = 'authorized.onmicrosoft.com'
                Recurrence   = '0'
            }
        }
    }

    It 'overrides a mismatched stored Tenant with the authorized task tenant' {
        $Item = $script:BaseItem.Clone()
        $Item.Parameters = @{
            Tenant                 = 'victim.onmicrosoft.com'
            AuthenticationMethodId = 'SMS'
            Enabled                = $true
        }

        Push-ExecScheduledCommand -Item ([pscustomobject]$Item)

        $script:InvokedWith | Should -Not -BeNullOrEmpty
        # The command must have run against the task's authorized tenant, never the stored one.
        $script:InvokedWith.Tenant | Should -Be 'authorized.onmicrosoft.com'
        $script:InvokedWith.Tenant | Should -Not -Be 'victim.onmicrosoft.com'
    }

    It 'logs an Error when the stored tenant value differed from the authorized tenant' {
        $Item = $script:BaseItem.Clone()
        $Item.Parameters = @{
            Tenant                 = 'victim.onmicrosoft.com'
            AuthenticationMethodId = 'SMS'
            Enabled                = $true
        }

        Push-ExecScheduledCommand -Item ([pscustomobject]$Item)

        Should -Invoke -CommandName Write-LogMessage -Times 1 -ParameterFilter {
            $sev -eq 'Error' -and $message -match 'victim\.onmicrosoft\.com' -and $message -match 'authorized\.onmicrosoft\.com'
        }
    }

    It 'runs cleanly with no Error log when no tenant parameter is stored' {
        $Item = $script:BaseItem.Clone()
        $Item.Parameters = @{
            AuthenticationMethodId = 'SMS'
            Enabled                = $true
        }

        Push-ExecScheduledCommand -Item ([pscustomobject]$Item)

        $script:InvokedWith.Tenant | Should -Be 'authorized.onmicrosoft.com'
        Should -Invoke -CommandName Write-LogMessage -Times 0 -ParameterFilter {
            $sev -eq 'Error' -and $message -match 'does not match the authorized tenant'
        }
    }

    It 'blocks a matching function that is not in an allowed CIPP module' {
        function Get-CIPPOutsideReport { param($Tenant) $script:InvokedWith = @{ Tenant = $Tenant } }
        $Item = $script:BaseItem.Clone()
        $Item.Command = 'Get-CIPPOutsideReport'
        $Item.Parameters = @{}

        Push-ExecScheduledCommand -Item ([pscustomobject]$Item)

        $script:InvokedWith | Should -BeNullOrEmpty
        Should -Invoke -CommandName Update-AzDataTableEntity -Times 1 -Exactly -ParameterFilter {
            $Entity.TaskState -eq 'Failed' -and $Entity.Results -like "Task blocked*Get-CIPPOutsideReport*"
        }
    }
}
