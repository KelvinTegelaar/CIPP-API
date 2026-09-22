# Regression tests for the scheduler tenant-authorization gap (INC-2026-003 Finding 3).
#
# A scheduled command's own tenant parameter (Tenant / TenantId, or an explicit TenantFilter in the
# stored Parameters) used to be persisted verbatim and executed with no authorization check against
# the caller's allowed-tenant scope. Only the picker's TenantFilter was authorized. This let a task
# created against tenant A carry a Parameters.Tenant of tenant B and run unchecked.
#
# Creation-time defense (this file): Add-CIPPScheduledTask strips any tenant-identifying parameter
# from the stored Parameters and logs at Error when the stored value pointed at a different tenant
# than the picked one. The authorized tenant is injected at execution instead (see the companion
# Push-ExecScheduledCommand.TenantCoercion.Tests.ps1).

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

    # Build a synthetic Get-Command result: the real Add-CIPPScheduledTask gates on $Command.Module
    # (must be an allowed CIPP module) and reads $Command.Parameters.ContainsKey(...). Rather than
    # register real functions in a fake module, hand back an object with just those two surfaces.
    function New-FakeCommand {
        param([string]$Module = 'CIPPCore', [string[]]$ParamNames)
        $params = @{}
        foreach ($p in $ParamNames) { $params[$p] = [pscustomobject]@{ Name = $p } }
        [pscustomobject]@{ Module = $Module; Parameters = $params }
    }

    # Capture what actually gets written to the ScheduledTasks table.
    $script:CapturedEntity = $null
    $script:LoggedErrors = [System.Collections.Generic.List[string]]::new()
}

Describe 'Add-CIPPScheduledTask tenant-parameter coercion' {
    BeforeEach {
        $script:CapturedEntity = $null
        $script:LoggedErrors = [System.Collections.Generic.List[string]]::new()
        Mock -CommandName Get-CIPPTable -MockWith { @{ Context = 'stub' } }
        Mock -CommandName Get-CIPPAzDataTableEntity -MockWith { $null }
        Mock -CommandName Add-CIPPAzDataTableEntity -MockWith { $script:CapturedEntity = $Entity }
        Mock -CommandName Update-AzDataTableEntity -MockWith { }
        Mock -CommandName Add-CippQueueMessage -MockWith { }
        Mock -CommandName Write-LogMessage -MockWith {
            if ($Sev -eq 'Error') { $script:LoggedErrors.Add([string]$message) }
        }
        # Default: a command that declares its own -Tenant parameter (the gap shape). Individual
        # tests override this for the no-tenant-parameter case.
        Mock -CommandName Get-Command -MockWith {
            New-FakeCommand -ParamNames @('TenantFilter', 'AuthenticationMethodId', 'Enabled')
        }
    }

    It 'strips a mismatched Tenant parameter so it is never persisted' {
        $Task = [pscustomobject]@{
            Name         = 'Evil cross-tenant task'
            Command      = 'Set-CIPPAuthenticationPolicy'
            TenantFilter = 'authorized.onmicrosoft.com'
            Parameters   = [pscustomobject]@{
                Tenant                 = 'victim.onmicrosoft.com'
                AuthenticationMethodId = 'SMS'
                Enabled                = $true
            }
        }

        Add-CIPPScheduledTask -Task $Task

        $script:CapturedEntity | Should -Not -BeNullOrEmpty
        $StoredParams = $script:CapturedEntity.Parameters | ConvertFrom-Json
        # The tenant-identifying key must be gone; the benign parameters survive.
        $StoredParams.PSObject.Properties.Name | Should -Not -Contain 'Tenant'
        $StoredParams.AuthenticationMethodId | Should -Be 'SMS'
        # The task's own tenant scope is still the authorized picker value.
        $script:CapturedEntity.Tenant | Should -Be 'authorized.onmicrosoft.com'
    }

    It 'logs an Error naming both tenants when the stored value points elsewhere' {
        $Task = [pscustomobject]@{
            Name         = 'Evil cross-tenant task'
            Command      = 'Set-CIPPAuthenticationPolicy'
            TenantFilter = 'authorized.onmicrosoft.com'
            Parameters   = [pscustomobject]@{
                Tenant                 = 'victim.onmicrosoft.com'
                AuthenticationMethodId = 'SMS'
                Enabled                = $true
            }
        }

        Add-CIPPScheduledTask -Task $Task

        $script:LoggedErrors.Count | Should -BeGreaterThan 0
        ($script:LoggedErrors -join "`n") | Should -Match 'victim\.onmicrosoft\.com'
        ($script:LoggedErrors -join "`n") | Should -Match 'authorized\.onmicrosoft\.com'
    }

    It 'strips a matching Tenant parameter silently (no Error) since execution re-injects it' {
        $Task = [pscustomobject]@{
            Name         = 'Legit task'
            Command      = 'Set-CIPPAuthenticationPolicy'
            TenantFilter = 'authorized.onmicrosoft.com'
            Parameters   = [pscustomobject]@{
                Tenant                 = 'authorized.onmicrosoft.com'
                AuthenticationMethodId = 'SMS'
                Enabled                = $true
            }
        }

        Add-CIPPScheduledTask -Task $Task

        $StoredParams = $script:CapturedEntity.Parameters | ConvertFrom-Json
        $StoredParams.PSObject.Properties.Name | Should -Not -Contain 'Tenant'
        $script:LoggedErrors.Count | Should -Be 0
    }

    It 'leaves non-tenant parameters untouched for a command with no tenant parameter' {
        function Get-CIPPHarmlessThing { param($Foo, $Bar) }
        Mock -CommandName Get-CIPPAzDataTableEntity -MockWith { $null }

        $Task = [pscustomobject]@{
            Name         = 'Harmless task'
            Command      = 'Get-CIPPHarmlessThing'
            TenantFilter = 'authorized.onmicrosoft.com'
            Parameters   = [pscustomobject]@{ Foo = 'a'; Bar = 'b' }
        }

        Add-CIPPScheduledTask -Task $Task

        $StoredParams = $script:CapturedEntity.Parameters | ConvertFrom-Json
        $StoredParams.Foo | Should -Be 'a'
        $StoredParams.Bar | Should -Be 'b'
        $script:LoggedErrors.Count | Should -Be 0
    }
}
