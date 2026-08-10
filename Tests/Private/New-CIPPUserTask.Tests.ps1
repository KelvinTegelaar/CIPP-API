# Pester tests for New-CIPPUserTask
# Covers the shared-calendar onboarding block: one scheduled Set-CIPPCalendarPermission task per
# calendar, the sharing-invitation flag, the Editor fallback, plain-string calendar entries, the
# no-calendars case, and the guard that only shared mailboxes of the tenant can be targeted.

BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
    $FunctionPath = Get-ChildItem -Path (Join-Path $RepoRoot 'Modules') -Recurse -Filter 'New-CIPPUserTask.ps1' -File -ErrorAction SilentlyContinue |
        Select-Object -First 1 -ExpandProperty FullName
    if (-not $FunctionPath) { throw 'Could not locate New-CIPPUserTask.ps1 under Modules/' }

    function New-CIPPUser { param($UserObj, $APIName, $Headers) }
    function Set-CIPPUserLicense { param($UserId, $TenantFilter, $AddLicenses, $Headers, $APIName) }
    function Set-SherwebSubscription { param($Headers, $TenantFilter, $SKU, $Add) }
    function Add-CIPPAlias { param($User, $Aliases, $UserPrincipalName, $TenantFilter, $APIName, $Headers) }
    function Set-CIPPCopyGroupMembers { param($Headers, $CopyFromId, $UserID, $TenantFilter) }
    function Add-CIPPGroupMember { param($Headers, $GroupType, $GroupId, $Member, $TenantFilter, $APIName) }
    function Set-CIPPManager { param($Users, $Manager, $TenantFilter, $Headers) }
    function Set-CIPPSponsor { param($Users, $Sponsor, $TenantFilter, $Headers) }
    function Add-CIPPScheduledTask { param($Task, $hidden, $Headers, $DisallowDuplicateName) }
    function New-ExoRequest { param($tenantid, $cmdlet, $cmdParams, $Select, $Anchor, $useSystemMailbox) }
    function Write-LogMessage { param($headers, $API, $tenant, $message, $Sev, $LogData) }

    . $FunctionPath

    # Minimal user object: only the shared-calendar branch should do anything.
    function New-TestUserObj {
        param($SharedCalendars, $SharedCalendarPermission, $SharedMailboxes, $SharedMailboxPermission)
        $UserObj = [pscustomobject]@{
            tenantFilter = 'contoso.com'
            givenName    = 'New'
            surname      = 'User'
        }
        foreach ($Field in @('SharedCalendars', 'SharedCalendarPermission', 'SharedMailboxes', 'SharedMailboxPermission')) {
            if ($PSBoundParameters.ContainsKey($Field)) {
                # The request body uses camelCase, matching what the Add User form posts.
                $Name = $Field.Substring(0, 1).ToLower() + $Field.Substring(1)
                $UserObj | Add-Member -NotePropertyName $Name -NotePropertyValue $PSBoundParameters[$Field]
            }
        }
        return $UserObj
    }
}

Describe 'New-CIPPUserTask' {
    BeforeEach {
        Mock -CommandName New-CIPPUser -MockWith {
            [pscustomobject]@{
                Username = 'new.user@contoso.com'
                Password = 'Correct-Horse-Battery'
                User     = [pscustomobject]@{ id = 'user-guid' }
            }
        }
        Mock -CommandName Add-CIPPScheduledTask -MockWith { 'Successfully added task: Grant Calendar Access. It will run in 15 minutes.' }
        Mock -CommandName Write-LogMessage -MockWith { }
        Mock -CommandName New-ExoRequest -MockWith {
            @(
                [pscustomobject]@{ UserPrincipalName = 'facility@contoso.com'; PrimarySmtpAddress = 'facility@contoso.com' }
                [pscustomobject]@{ UserPrincipalName = 'reception@contoso.com'; PrimarySmtpAddress = 'reception@contoso.com' }
            )
        }
    }

    Context 'Shared calendar onboarding' {
        It 'schedules one calendar permission task per shared calendar, with the invitation flag set' {
            $UserObj = New-TestUserObj -SharedCalendars @(
                [pscustomobject]@{ label = 'Facility (facility@contoso.com)'; value = 'facility@contoso.com' }
                [pscustomobject]@{ label = 'Reception (reception@contoso.com)'; value = 'reception@contoso.com' }
            ) -SharedCalendarPermission ([pscustomobject]@{ label = 'Reviewer'; value = 'Reviewer' })

            $null = New-CIPPUserTask -UserObj $UserObj

            Should -Invoke Add-CIPPScheduledTask -Times 2 -Exactly
            Should -Invoke Add-CIPPScheduledTask -Times 1 -Exactly -ParameterFilter {
                $Task.Command.value -eq 'Set-CIPPCalendarPermission' -and
                $Task.Parameters.UserID -eq 'facility@contoso.com' -and
                $Task.Parameters.UserToGetPermissions -eq 'new.user@contoso.com' -and
                $Task.Parameters.SendNotificationToUser -eq $true -and
                $Task.Parameters.AutoResolveFolderName -eq $true -and
                $Task.Parameters.FolderName -eq 'Calendar' -and
                $Task.Parameters.Permissions -eq 'Reviewer' -and
                $Task.Parameters.TenantFilter -eq 'contoso.com' -and
                $Task.TenantFilter -eq 'contoso.com'
            }
        }

        It 'schedules the grant 15 minutes out so Exchange can provision the mailbox first' {
            $UserObj = New-TestUserObj -SharedCalendars @(
                [pscustomobject]@{ label = 'Facility'; value = 'facility@contoso.com' }
            )
            $Expected = [int64](([datetime]::UtcNow).AddMinutes(15) - (Get-Date '1/1/1970')).TotalSeconds

            $null = New-CIPPUserTask -UserObj $UserObj

            Should -Invoke Add-CIPPScheduledTask -Times 1 -Exactly -ParameterFilter {
                [math]::Abs($Task.ScheduledTime - $Expected) -lt 60
            }
        }

        It 'falls back to Editor when the template has no permission level' {
            $UserObj = New-TestUserObj -SharedCalendars @(
                [pscustomobject]@{ label = 'Facility'; value = 'facility@contoso.com' }
            )

            $null = New-CIPPUserTask -UserObj $UserObj

            Should -Invoke Add-CIPPScheduledTask -Times 1 -Exactly -ParameterFilter {
                $Task.Parameters.Permissions -eq 'Editor'
            }
        }

        It 'accepts a plain string calendar entry and a plain string permission level' {
            $UserObj = New-TestUserObj -SharedCalendars @('facility@contoso.com') -SharedCalendarPermission 'LimitedDetails'

            $null = New-CIPPUserTask -UserObj $UserObj

            Should -Invoke Add-CIPPScheduledTask -Times 1 -Exactly -ParameterFilter {
                $Task.Parameters.UserID -eq 'facility@contoso.com' -and
                $Task.Parameters.Permissions -eq 'LimitedDetails'
            }
        }

        It 'reports the scheduled grant back to the caller' {
            $UserObj = New-TestUserObj -SharedCalendars @(
                [pscustomobject]@{ label = 'Facility (facility@contoso.com)'; value = 'facility@contoso.com' }
            )

            $Result = New-CIPPUserTask -UserObj $UserObj

            $Result.Results | Should -Contain 'Scheduled Editor access to the calendar of Facility (facility@contoso.com) in 15 minutes. A sharing invitation will be sent to new.user@contoso.com once Exchange has provisioned the mailbox.'
        }

        It 'does not fail user creation when scheduling the grant throws' {
            Mock -CommandName Add-CIPPScheduledTask -MockWith { throw 'scheduler unavailable' }
            $UserObj = New-TestUserObj -SharedCalendars @(
                [pscustomobject]@{ label = 'Facility'; value = 'facility@contoso.com' }
            )

            $Result = New-CIPPUserTask -UserObj $UserObj

            $Result.Username | Should -Be 'new.user@contoso.com'
            $Result.Results | Should -Contain 'Failed to schedule calendar access to Facility: scheduler unavailable'
        }

        It 'refuses to grant access to a mailbox that is not a shared mailbox of the tenant' {
            # Guard against Identity.User.ReadWrite callers granting the new account access to a
            # person's calendar by POSTing an arbitrary address to /api/AddUser.
            $UserObj = New-TestUserObj -SharedCalendars @(
                [pscustomobject]@{ label = 'CEO'; value = 'ceo@contoso.com' }
                [pscustomobject]@{ label = 'Facility'; value = 'facility@contoso.com' }
            )

            $Result = New-CIPPUserTask -UserObj $UserObj

            Should -Invoke Add-CIPPScheduledTask -Times 1 -Exactly -ParameterFilter {
                $Task.Parameters.UserID -eq 'facility@contoso.com'
            }
            Should -Invoke Add-CIPPScheduledTask -Times 0 -Exactly -ParameterFilter {
                $Task.Parameters.UserID -eq 'ceo@contoso.com'
            }
            $Result.Results | Should -Contain 'Skipped calendar access to CEO: it is not a shared mailbox in this tenant.'
        }

        It 'grants nothing when the shared mailbox lookup fails' {
            Mock -CommandName New-ExoRequest -MockWith { throw 'Exchange unavailable' }
            $UserObj = New-TestUserObj -SharedCalendars @(
                [pscustomobject]@{ label = 'Facility'; value = 'facility@contoso.com' }
            )

            $Result = New-CIPPUserTask -UserObj $UserObj

            Should -Invoke Add-CIPPScheduledTask -Times 0 -Exactly
            $Result.Results | Should -Contain 'Could not verify the shared mailboxes for this tenant, no shared access was granted: Exchange unavailable'
        }

        It 'reports a failure when the scheduler rejects the task instead of throwing' {
            Mock -CommandName Add-CIPPScheduledTask -MockWith { 'Task with name Grant Calendar Access already exists' }
            $UserObj = New-TestUserObj -SharedCalendars @(
                [pscustomobject]@{ label = 'Facility'; value = 'facility@contoso.com' }
            )

            $Result = New-CIPPUserTask -UserObj $UserObj

            $Result.Results | Should -Contain 'Failed to schedule calendar access to Facility: Task with name Grant Calendar Access already exists'
        }

        It 'schedules nothing when no shared calendars are configured' {
            $UserObj = New-TestUserObj

            $null = New-CIPPUserTask -UserObj $UserObj

            Should -Invoke Add-CIPPScheduledTask -Times 0 -Exactly
        }
    }

    Context 'Shared mailbox onboarding' {
        It 'schedules a mailbox permission task with automapping so Outlook mounts the mailbox' {
            $UserObj = New-TestUserObj -SharedMailboxes @(
                [pscustomobject]@{ label = 'Facility'; value = 'facility@contoso.com' }
            )

            $Result = New-CIPPUserTask -UserObj $UserObj

            Should -Invoke Add-CIPPScheduledTask -Times 1 -Exactly -ParameterFilter {
                $Task.Command.value -eq 'Set-CIPPMailboxPermission' -and
                $Task.Parameters.UserId -eq 'facility@contoso.com' -and
                $Task.Parameters.AccessUser -eq 'new.user@contoso.com' -and
                $Task.Parameters.PermissionLevel -eq 'FullAccess' -and
                $Task.Parameters.Action -eq 'Add' -and
                $Task.Parameters.AutoMap -eq $true
            }
            $Result.Results | Should -Contain 'Scheduled FullAccess on the shared mailbox Facility in 15 minutes. Outlook adds the mailbox automatically.'
        }

        It 'honours a non-default permission level and drops the automapping note' {
            $UserObj = New-TestUserObj -SharedMailboxes @(
                [pscustomobject]@{ label = 'Facility'; value = 'facility@contoso.com' }
            ) -SharedMailboxPermission ([pscustomobject]@{ label = 'SendAs'; value = 'SendAs' })

            $Result = New-CIPPUserTask -UserObj $UserObj

            Should -Invoke Add-CIPPScheduledTask -Times 1 -Exactly -ParameterFilter {
                $Task.Parameters.PermissionLevel -eq 'SendAs'
            }
            $Result.Results | Should -Contain 'Scheduled SendAs on the shared mailbox Facility in 15 minutes.'
        }

        It 'schedules one task per permission level when several are selected' {
            $UserObj = New-TestUserObj -SharedMailboxes @(
                [pscustomobject]@{ label = 'Facility'; value = 'facility@contoso.com' }
            ) -SharedMailboxPermission @(
                [pscustomobject]@{ label = 'Full Access'; value = 'FullAccess' }
                [pscustomobject]@{ label = 'Send As'; value = 'SendAs' }
            )

            $null = New-CIPPUserTask -UserObj $UserObj

            Should -Invoke Add-CIPPScheduledTask -Times 2 -Exactly
            Should -Invoke Add-CIPPScheduledTask -Times 1 -Exactly -ParameterFilter {
                $Task.Parameters.PermissionLevel -eq 'FullAccess' -and
                # The task name carries the level, otherwise DisallowDuplicateName drops the second one.
                $Task.Name -eq 'Grant Mailbox Access: new.user@contoso.com -> facility@contoso.com (FullAccess)'
            }
            Should -Invoke Add-CIPPScheduledTask -Times 1 -Exactly -ParameterFilter {
                $Task.Parameters.PermissionLevel -eq 'SendAs'
            }
        }

        It 'refuses a mailbox that is not a shared mailbox of the tenant' {
            $UserObj = New-TestUserObj -SharedMailboxes @(
                [pscustomobject]@{ label = 'CEO'; value = 'ceo@contoso.com' }
            )

            $Result = New-CIPPUserTask -UserObj $UserObj

            Should -Invoke Add-CIPPScheduledTask -Times 0 -Exactly
            $Result.Results | Should -Contain 'Skipped mailbox access to CEO: it is not a shared mailbox in this tenant.'
        }

        It 'schedules calendar and mailbox access side by side from a single lookup' {
            $UserObj = New-TestUserObj -SharedCalendars @(
                [pscustomobject]@{ label = 'Reception'; value = 'reception@contoso.com' }
            ) -SharedMailboxes @(
                [pscustomobject]@{ label = 'Facility'; value = 'facility@contoso.com' }
            )

            $null = New-CIPPUserTask -UserObj $UserObj

            Should -Invoke Add-CIPPScheduledTask -Times 2 -Exactly
            Should -Invoke New-ExoRequest -Times 1 -Exactly
            Should -Invoke Add-CIPPScheduledTask -Times 1 -Exactly -ParameterFilter {
                $Task.Command.value -eq 'Set-CIPPCalendarPermission'
            }
            Should -Invoke Add-CIPPScheduledTask -Times 1 -Exactly -ParameterFilter {
                $Task.Command.value -eq 'Set-CIPPMailboxPermission'
            }
        }
    }
}
