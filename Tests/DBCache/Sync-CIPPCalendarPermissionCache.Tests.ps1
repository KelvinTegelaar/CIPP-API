# Pester tests for Sync-CIPPCalendarPermissionCache (Remove path)
# Cached calendar permission rows are keyed 'UPN:\<Folder>', but ExecModifyCalPerms passes the
# mailbox's Entra object id. The sync must resolve that id back to the UPN to find the row.

BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))

    function Get-CIPPDbItem { param($TenantFilter, $Type) }
    function Add-CIPPDbItem { param([Parameter(ValueFromPipeline)]$InputObject, $TenantFilter, $Type, [switch]$Append) }
    function Remove-CIPPDbItem { param($TenantFilter, $Type, $ItemId) }
    function Get-CippTable { param($tablename) }
    function Get-CIPPAzDataTableEntity { param($Filter) }
    function Write-LogMessage { param($API, $tenant, $message, $sev) }

    . (Join-Path $RepoRoot 'Modules/CIPPCore/Public/Sync-CIPPCalendarPermissionCache.ps1')
}

Describe 'Sync-CIPPCalendarPermissionCache -Action Remove' {
    BeforeEach {
        Mock -CommandName Get-CIPPDbItem -MockWith {
            @([pscustomobject]@{
                    RowKey = 'Mailboxes-abc'
                    Data   = (@{ UPN = 'alice@contoso.com'; primarySmtpAddress = 'alice@contoso.com'; Id = 'exo-id-1'; ExternalDirectoryObjectId = '11111111-1111-1111-1111-111111111111'; displayName = 'Alice' } | ConvertTo-Json)
                })
        }
        Mock -CommandName Get-CippTable -MockWith { @{} }
        Mock -CommandName Get-CIPPAzDataTableEntity -MockWith {
            @(
                [pscustomobject]@{ RowKey = 'CalendarPermissions-row1'; Data = (@{ Identity = 'alice@contoso.com:\Kalender'; User = 'Bob Jones' } | ConvertTo-Json) }
                [pscustomobject]@{ RowKey = 'CalendarPermissions-row2'; Data = (@{ Identity = 'alice@contoso.com:\Kalender'; User = 'Carol' } | ConvertTo-Json) }
            )
        }
        Mock -CommandName Remove-CIPPDbItem -MockWith { }
        Mock -CommandName Add-CIPPDbItem -MockWith { }
        Mock -CommandName Write-LogMessage -MockWith { }
    }

    It 'removes the UPN-keyed row when given the Entra object id' {
        Sync-CIPPCalendarPermissionCache -TenantFilter 'contoso.com' -MailboxIdentity '11111111-1111-1111-1111-111111111111' -FolderName 'Kalender' -User 'Bob Jones' -Action 'Remove'
        Should -Invoke Remove-CIPPDbItem -Times 1 -Exactly -ParameterFilter { $ItemId -eq 'row1' }
    }

    It 'still removes the row when given the UPN' {
        Sync-CIPPCalendarPermissionCache -TenantFilter 'contoso.com' -MailboxIdentity 'alice@contoso.com' -FolderName 'Kalender' -User 'Carol' -Action 'Remove'
        Should -Invoke Remove-CIPPDbItem -Times 1 -Exactly -ParameterFilter { $ItemId -eq 'row2' }
    }

    It 'reads the tenant cache once when calls share a CacheContext' {
        $Context = @{}
        Sync-CIPPCalendarPermissionCache -TenantFilter 'contoso.com' -MailboxIdentity '11111111-1111-1111-1111-111111111111' -FolderName 'Kalender' -User 'Bob Jones' -Action 'Remove' -CacheContext $Context
        Sync-CIPPCalendarPermissionCache -TenantFilter 'contoso.com' -MailboxIdentity 'alice@contoso.com' -FolderName 'Kalender' -User 'Carol' -Action 'Remove' -CacheContext $Context
        # Already removed from the shared list, so a repeat must not delete anything again
        Sync-CIPPCalendarPermissionCache -TenantFilter 'contoso.com' -MailboxIdentity 'alice@contoso.com' -FolderName 'Kalender' -User 'Bob Jones' -Action 'Remove' -CacheContext $Context

        Should -Invoke Get-CIPPDbItem -Times 1 -Exactly
        Should -Invoke Get-CIPPAzDataTableEntity -Times 1 -Exactly
        Should -Invoke Remove-CIPPDbItem -Times 2 -Exactly
        $Context.CalendarPermissionRows.Count | Should -Be 0
    }

    It 'reloads the calendar rows after an Add on a shared CacheContext' {
        $Context = @{}
        Sync-CIPPCalendarPermissionCache -TenantFilter 'contoso.com' -MailboxIdentity 'alice@contoso.com' -FolderName 'Kalender' -User 'Carol' -Action 'Remove' -CacheContext $Context
        Sync-CIPPCalendarPermissionCache -TenantFilter 'contoso.com' -MailboxIdentity 'alice@contoso.com' -FolderName 'Kalender' -User 'alice@contoso.com' -Permissions 'Reviewer' -Action 'Add' -CacheContext $Context
        Sync-CIPPCalendarPermissionCache -TenantFilter 'contoso.com' -MailboxIdentity 'alice@contoso.com' -FolderName 'Kalender' -User 'Bob Jones' -Action 'Remove' -CacheContext $Context

        Should -Invoke Get-CIPPAzDataTableEntity -Times 2 -Exactly
        Should -Invoke Add-CIPPDbItem -Times 1 -Exactly
    }
}
