BeforeAll {
    . (Join-Path $PSScriptRoot '../../Modules/CIPPCore/Public/ConvertTo-CIPPODataFilterValue.ps1')
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
    . (Join-Path $RepoRoot 'Modules/CIPPCore/Public/Get-CIPPScheduledTaskNextRun.ps1')
    . (Join-Path $RepoRoot 'Modules/CIPPCore/Public/Tools/Get-CIPPPrivilegedUserTaskTarget.ps1')

    function Get-CippRequestAllowedPermissions { }
    function Assert-CippPrivilegedUserAccess { param($TenantFilter, $UserId, [switch]$Enforce) }
    function Get-CIPPBecReport { param($TenantFilter, $CaseId) }
    function Get-CIPPTable { param($TableName) }
    function Get-CIPPAzDataTableEntity { param($Context, $Filter, $Property) }
    function Add-CIPPAzDataTableEntity { param($Context, $Entity, [switch]$Force) }
    function Add-CippQueueMessage { param($Cmdlet, $Parameters) }
    function Get-CIPPSchedulerBlockedCommands { @() }
    function Resolve-CIPPCommand { param($Name) }
    function Get-NormalizedError { param($Message) $Message }
    function Write-LogMessage { param($headers, $API, $message, $Sev, $tenant, $tenantid, $LogData) }

    . (Join-Path $RepoRoot 'Modules/CIPPCore/Public/Add-CIPPScheduledTask.ps1')

    function New-ResetTask([string]$UserID = 'admin@contoso.com', $TenantFilter = 'contoso.onmicrosoft.com') {
        [pscustomobject]@{
            Name          = 'Reset'
            Command       = @{ value = 'Set-CIPPResetPassword' }
            TenantFilter  = $TenantFilter
            Parameters    = [pscustomobject]@{ UserID = $UserID }
            ScheduledTime = '0'
        }
    }
}

Describe 'Get-CIPPPrivilegedUserTaskTarget' {
    It 'returns nothing for a command that is not sensitive' {
        Get-CIPPPrivilegedUserTaskTarget -Command 'Set-CIPPOutOfOffice' -Parameters @{ UserID = 'a@b.com' } | Should -BeNullOrEmpty
    }

    It 'reads user ids, UPNs, picker objects, arrays and UserObj' {
        @(Get-CIPPPrivilegedUserTaskTarget -Command 'Set-CIPPSignInState' -Parameters @{ userid = @('a@b.com', 'c@b.com') }) | Should -Be @('a@b.com', 'c@b.com')
        @(Get-CIPPPrivilegedUserTaskTarget -Command 'Remove-CIPPUserMFA' -Parameters @{ UserPrincipalName = @{ label = 'A'; value = 'a@b.com' } }) | Should -Be @('a@b.com')
        @(Get-CIPPPrivilegedUserTaskTarget -Command 'Set-CIPPUser' -Parameters @{ UserObj = [pscustomobject]@{ id = 'id-1' } }) | Should -Be @('id-1')
    }

    It 'skips an unresolved %variable%' {
        Get-CIPPPrivilegedUserTaskTarget -Command 'Set-CIPPResetPassword' -Parameters @{ UserID = '%id%' } | Should -BeNullOrEmpty
    }

    It 'resolves a BEC release to the case user' {
        Mock Get-CIPPBecReport { [pscustomobject]@{ UserPrincipalName = 'victim@b.com' } }
        Get-CIPPPrivilegedUserTaskTarget -Command 'Invoke-CIPPBecRelease' -Parameters @{ CaseId = 'case-1' } -TenantFilter 't' | Should -Be 'victim@b.com'
    }
}

Describe 'Add-CIPPScheduledTask for privileged users' {
    BeforeEach {
        $script:CapturedEntity = $null
        Mock Get-CIPPTable { @{ Context = 'stub' } }
        Mock Get-CIPPAzDataTableEntity { $null }
        Mock Add-CIPPAzDataTableEntity { $script:CapturedEntity = $Entity }
        Mock Add-CippQueueMessage { $true }
        Mock Resolve-CIPPCommand { [pscustomobject]@{ Name = $Name; ModuleName = 'CIPPCore' } }
        Mock Get-CippRequestAllowedPermissions { , @('CIPP.Scheduler.ReadWrite') }
        Mock Assert-CippPrivilegedUserAccess {}
    }

    It 'refuses a task that targets a privileged user and stores nothing' {
        Mock Assert-CippPrivilegedUserAccess { throw [System.UnauthorizedAccessException]::new('admin@contoso.com holds a privileged admin role.') }

        Add-CIPPScheduledTask -Task (New-ResetTask) | Should -BeLike 'Error - admin@contoso.com holds a privileged admin role.*'
        $script:CapturedEntity | Should -BeNullOrEmpty
    }

    It 'flags the task for a run-time check when the caller lacks the permission' {
        Add-CIPPScheduledTask -Task (New-ResetTask -UserID 'user@contoso.com')

        Should -Invoke Assert-CippPrivilegedUserAccess -Times 1 -Exactly -ParameterFilter { $Enforce -and $UserId -contains 'user@contoso.com' }
        $script:CapturedEntity.PrivilegedUserRestricted | Should -BeTrue
    }

    It 'leaves %variable% users and all-tenant tasks to the run-time check' {
        Add-CIPPScheduledTask -Task (New-ResetTask -UserID '%id%')
        $script:CapturedEntity.PrivilegedUserRestricted | Should -BeTrue
        Add-CIPPScheduledTask -Task (New-ResetTask -TenantFilter 'AllTenants')
        $script:CapturedEntity.PrivilegedUserRestricted | Should -BeTrue

        Should -Invoke Assert-CippPrivilegedUserAccess -Times 0 -Exactly
    }

    It 'does not flag or check for a caller with the permission' {
        Mock Get-CippRequestAllowedPermissions { , @('Identity.PrivilegedUser.ReadWrite') }

        Add-CIPPScheduledTask -Task (New-ResetTask)

        Should -Invoke Assert-CippPrivilegedUserAccess -Times 0 -Exactly
        $script:CapturedEntity.Keys | Should -Not -Contain 'PrivilegedUserRestricted'
    }

    It 'does not flag background callers' {
        Mock Get-CippRequestAllowedPermissions { $null }

        Add-CIPPScheduledTask -Task (New-ResetTask)

        $script:CapturedEntity.Keys | Should -Not -Contain 'PrivilegedUserRestricted'
    }

    It 'flags an existing task when a caller without the permission runs it now' {
        Mock Get-CIPPAzDataTableEntity { [pscustomobject]@{ PartitionKey = 'ScheduledTask'; RowKey = 'abc'; Name = 'Existing'; ScheduledTime = '0'; TaskState = 'Completed' } }

        $null = Add-CIPPScheduledTask -RunNow -RowKey 'abc'

        $script:CapturedEntity.PrivilegedUserRestricted | Should -BeTrue
    }
}
