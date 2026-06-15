# Pester tests for Set-CIPPMailboxVacation
# Covers the mailbox-permission loop (delegating to Set-CIPPMailboxPermission), the calendar-permission
# loop (Set-CIPPCalendarPermission), hashtable vs PSCustomObject entry access, missing-field skips,
# Action propagation, and the calendar error path.

BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
    $FunctionPath = Get-ChildItem -Path (Join-Path $RepoRoot 'Modules') -Recurse -Filter 'Set-CIPPMailboxVacation.ps1' -File -ErrorAction SilentlyContinue |
        Select-Object -First 1 -ExpandProperty FullName
    if (-not $FunctionPath) { throw 'Could not locate Set-CIPPMailboxVacation.ps1 under Modules/' }

    function Set-CIPPMailboxPermission { param($UserId, $AccessUser, $PermissionLevel, $Action, $AutoMap, $TenantFilter, $APIName, $Headers) }
    function Set-CIPPCalendarPermission { param($TenantFilter, $UserID, $FolderName, $APIName, $Headers, $RemoveAccess, $UserToGetPermissions, $Permissions, $CanViewPrivateItems) }
    function Get-CippException { param($Exception) }

    . $FunctionPath
}

Describe 'Set-CIPPMailboxVacation' {
    BeforeEach {
        Mock -CommandName Set-CIPPMailboxPermission -MockWith { 'mailbox-perm-result' }
        Mock -CommandName Set-CIPPCalendarPermission -MockWith { 'calendar-perm-result' }
        Mock -CommandName Get-CippException -MockWith { [pscustomobject]@{ NormalizedError = 'boom' } }
    }

    Context 'Mailbox permissions' {
        It 'forwards each mailbox permission to Set-CIPPMailboxPermission with the requested Action' {
            $perms = @(
                [pscustomobject]@{ UserId = 'shared@contoso.com'; AccessUser = 'user@contoso.com'; PermissionLevel = 'FullAccess'; AutoMap = $true }
            )

            $results = Set-CIPPMailboxVacation -TenantFilter 'contoso.com' -Action 'Add' -MailboxPermissions $perms

            Should -Invoke Set-CIPPMailboxPermission -Times 1 -Exactly -ParameterFilter {
                $UserId -eq 'shared@contoso.com' -and
                $AccessUser -eq 'user@contoso.com' -and
                $PermissionLevel -eq 'FullAccess' -and
                $Action -eq 'Add' -and
                $AutoMap -eq $true -and
                $TenantFilter -eq 'contoso.com'
            }
            $results | Should -Contain 'mailbox-perm-result'
        }

        It 'propagates the Remove action to the delegate cmdlet' {
            $perms = @([pscustomobject]@{ UserId = 'shared@contoso.com'; AccessUser = 'user@contoso.com'; PermissionLevel = 'SendAs' })

            Set-CIPPMailboxVacation -TenantFilter 'contoso.com' -Action 'Remove' -MailboxPermissions $perms

            Should -Invoke Set-CIPPMailboxPermission -Times 1 -Exactly -ParameterFilter { $Action -eq 'Remove' }
        }

        It 'accepts hashtable entries as well as PSCustomObject entries' {
            $perms = @(@{ UserId = 'shared@contoso.com'; AccessUser = 'user@contoso.com'; PermissionLevel = 'FullAccess' })

            Set-CIPPMailboxVacation -TenantFilter 'contoso.com' -Action 'Add' -MailboxPermissions $perms

            Should -Invoke Set-CIPPMailboxPermission -Times 1 -Exactly -ParameterFilter { $UserId -eq 'shared@contoso.com' }
        }

        It 'defaults AutoMap to $true when not supplied' {
            $perms = @([pscustomobject]@{ UserId = 'shared@contoso.com'; AccessUser = 'user@contoso.com'; PermissionLevel = 'FullAccess' })

            Set-CIPPMailboxVacation -TenantFilter 'contoso.com' -Action 'Add' -MailboxPermissions $perms

            Should -Invoke Set-CIPPMailboxPermission -Times 1 -Exactly -ParameterFilter { $AutoMap -eq $true }
        }

        It 'skips entries with missing required fields and records a skip message' {
            $perms = @([pscustomobject]@{ UserId = 'shared@contoso.com'; PermissionLevel = 'FullAccess' }) # no AccessUser

            $results = Set-CIPPMailboxVacation -TenantFilter 'contoso.com' -Action 'Add' -MailboxPermissions $perms

            Should -Invoke Set-CIPPMailboxPermission -Times 0 -Exactly
            $results | Should -Contain 'Skipped mailbox permission with missing fields'
        }
    }

    Context 'Calendar permissions' {
        It 'forwards Add calendar permissions with delegate, permissions and private-items flag' {
            $cal = @(
                [pscustomobject]@{ UserID = 'shared@contoso.com'; UserToGetPermissions = 'user@contoso.com'; FolderName = 'Calendar'; Permissions = 'Editor'; CanViewPrivateItems = $true }
            )

            $results = Set-CIPPMailboxVacation -TenantFilter 'contoso.com' -Action 'Add' -CalendarPermissions $cal

            Should -Invoke Set-CIPPCalendarPermission -Times 1 -Exactly -ParameterFilter {
                $UserID -eq 'shared@contoso.com' -and
                $UserToGetPermissions -eq 'user@contoso.com' -and
                $Permissions -eq 'Editor' -and
                $CanViewPrivateItems -eq $true
            }
            $results | Should -Contain 'calendar-perm-result'
        }

        It 'uses RemoveAccess when the action is Remove' {
            $cal = @([pscustomobject]@{ UserID = 'shared@contoso.com'; UserToGetPermissions = 'user@contoso.com' })

            Set-CIPPMailboxVacation -TenantFilter 'contoso.com' -Action 'Remove' -CalendarPermissions $cal

            Should -Invoke Set-CIPPCalendarPermission -Times 1 -Exactly -ParameterFilter {
                $RemoveAccess -eq 'user@contoso.com'
            }
        }

        It 'defaults the calendar folder name to Calendar' {
            $cal = @([pscustomobject]@{ UserID = 'shared@contoso.com'; UserToGetPermissions = 'user@contoso.com' })

            Set-CIPPMailboxVacation -TenantFilter 'contoso.com' -Action 'Add' -CalendarPermissions $cal

            Should -Invoke Set-CIPPCalendarPermission -Times 1 -Exactly -ParameterFilter { $FolderName -eq 'Calendar' }
        }

        It 'skips calendar entries with missing required fields' {
            $cal = @([pscustomobject]@{ UserID = 'shared@contoso.com' }) # no delegate

            $results = Set-CIPPMailboxVacation -TenantFilter 'contoso.com' -Action 'Add' -CalendarPermissions $cal

            Should -Invoke Set-CIPPCalendarPermission -Times 0 -Exactly
            $results | Should -Contain 'Skipped calendar permission with missing fields'
        }

        It 'records a failure message when the calendar permission throws' {
            Mock -CommandName Set-CIPPCalendarPermission -MockWith { throw 'cal down' }
            $cal = @([pscustomobject]@{ UserID = 'shared@contoso.com'; UserToGetPermissions = 'user@contoso.com' })

            $results = Set-CIPPMailboxVacation -TenantFilter 'contoso.com' -Action 'Add' -CalendarPermissions $cal

            $results | Should -Match 'Failed calendar permission for user@contoso.com on shared@contoso.com: boom'
        }
    }
}
