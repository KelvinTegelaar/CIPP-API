# Pester tests for Set-CIPPVacationOOO.
#
# The out-of-office half of Vacation Mode. The wizard schedules two runs of this per vacation - an
# 'Add' at the start date and a 'Remove' at the end - so the two actions are not symmetric:
#
#   * Add with dates sets Exchange's own Scheduled state, so Exchange owns the window rather than
#     CIPP having to be up at the right moment.
#   * Remove only disables. It deliberately does NOT push messages back, because the person may
#     have edited their own auto-reply while away and a scheduled task should not overwrite that.
#
# One user's failure must not stop the rest of the batch.

BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
    $FunctionPath = Get-ChildItem -Path (Join-Path $RepoRoot 'Modules') -Recurse -Filter 'Set-CIPPVacationOOO.ps1' -File -ErrorAction SilentlyContinue |
        Select-Object -First 1 -ExpandProperty FullName
    if (-not $FunctionPath) { throw 'Could not locate Set-CIPPVacationOOO.ps1 under Modules/' }

    function Set-CIPPOutOfOffice {
        param(
            $UserID, $TenantFilter, $State, $APIName, $Headers, $StartTime, $EndTime,
            $InternalMessage, $ExternalMessage, $CreateOOFEvent, $OOFEventSubject,
            $AutoDeclineFutureRequestsWhenOOF, $DeclineEventsForScheduledOOF,
            $DeclineAllEventsForScheduledOOF, $DeclineMeetingMessage
        )
    }
    function Write-LogMessage { param($headers, $API, $tenant, $message, $Sev, $LogData) }
    function Get-CippException { param($Exception) @{ NormalizedError = "$Exception" } }

    . $FunctionPath
}

Describe 'Set-CIPPVacationOOO' {
    BeforeEach {
        Mock -CommandName Write-LogMessage -MockWith { }
        Mock -CommandName Set-CIPPOutOfOffice -MockWith { 'Successfully set out of office' }
    }

    Context 'Turning vacation on' {
        It 'hands the window to Exchange as a Scheduled auto-reply' {
            $Start = '2026-08-10T09:00:00'
            $End = '2026-08-24T17:00:00'

            $Result = Set-CIPPVacationOOO -TenantFilter 'contoso.com' -Action 'Add' -Users @('sseck@contoso.com') `
                -StartTime $Start -EndTime $End -InternalMessage 'Away' -ExternalMessage 'Out of office'

            Should -Invoke Set-CIPPOutOfOffice -Times 1 -Exactly -ParameterFilter {
                $UserID -eq 'sseck@contoso.com' -and
                $State -eq 'Scheduled' -and
                $StartTime -eq $Start -and
                $EndTime -eq $End -and
                $InternalMessage -eq 'Away' -and
                $ExternalMessage -eq 'Out of office' -and
                $TenantFilter -eq 'contoso.com'
            }
            $Result | Should -Contain 'Successfully set out of office'
        }

        It 'falls back to Enabled when no window was given' {
            # In-flight tasks queued before vacation carried dates still have to work.
            $null = Set-CIPPVacationOOO -TenantFilter 'contoso.com' -Action 'Add' -Users @('sseck@contoso.com') -InternalMessage 'Away'

            Should -Invoke Set-CIPPOutOfOffice -Times 1 -Exactly -ParameterFilter { $State -eq 'Enabled' }
        }

        It 'omits a message that was left blank rather than clearing the existing one' {
            $null = Set-CIPPVacationOOO -TenantFilter 'contoso.com' -Action 'Add' -Users @('sseck@contoso.com') `
                -InternalMessage 'Away' -ExternalMessage '   '

            Should -Invoke Set-CIPPOutOfOffice -Times 1 -Exactly -ParameterFilter {
                $InternalMessage -eq 'Away' -and $null -eq $ExternalMessage
            }
        }

        It 'passes the calendar options through when the wizard set them' {
            $null = Set-CIPPVacationOOO -TenantFilter 'contoso.com' -Action 'Add' -Users @('sseck@contoso.com') `
                -CreateOOFEvent $true -OOFEventSubject 'On leave' -AutoDeclineFutureRequestsWhenOOF $true `
                -DeclineEventsForScheduledOOF $true -DeclineAllEventsForScheduledOOF $false -DeclineMeetingMessage 'Back on the 24th'

            Should -Invoke Set-CIPPOutOfOffice -Times 1 -Exactly -ParameterFilter {
                $CreateOOFEvent -eq $true -and
                $OOFEventSubject -eq 'On leave' -and
                $AutoDeclineFutureRequestsWhenOOF -eq $true -and
                $DeclineEventsForScheduledOOF -eq $true -and
                $DeclineAllEventsForScheduledOOF -eq $false -and
                $DeclineMeetingMessage -eq 'Back on the 24th'
            }
        }

        It 'leaves the calendar options untouched when the wizard did not set them' {
            $null = Set-CIPPVacationOOO -TenantFilter 'contoso.com' -Action 'Add' -Users @('sseck@contoso.com')

            Should -Invoke Set-CIPPOutOfOffice -Times 1 -Exactly -ParameterFilter {
                $null -eq $CreateOOFEvent -and $null -eq $OOFEventSubject -and $null -eq $DeclineMeetingMessage
            }
        }
    }

    Context 'Turning vacation off' {
        It 'disables the auto-reply' {
            $Result = Set-CIPPVacationOOO -TenantFilter 'contoso.com' -Action 'Remove' -Users @('sseck@contoso.com')

            Should -Invoke Set-CIPPOutOfOffice -Times 1 -Exactly -ParameterFilter {
                $State -eq 'Disabled' -and $UserID -eq 'sseck@contoso.com'
            }
            $Result | Should -Contain 'Successfully set out of office'
        }

        It 'does not push messages back on the way out' {
            # The person may have rewritten their own auto-reply while away.
            $null = Set-CIPPVacationOOO -TenantFilter 'contoso.com' -Action 'Remove' -Users @('sseck@contoso.com') `
                -InternalMessage 'Away' -ExternalMessage 'Out of office'

            Should -Invoke Set-CIPPOutOfOffice -Times 1 -Exactly -ParameterFilter {
                $null -eq $InternalMessage -and $null -eq $ExternalMessage
            }
        }

        It 'does not send a window on the way out' {
            $null = Set-CIPPVacationOOO -TenantFilter 'contoso.com' -Action 'Remove' -Users @('sseck@contoso.com') `
                -StartTime '2026-08-10T09:00:00' -EndTime '2026-08-24T17:00:00'

            Should -Invoke Set-CIPPOutOfOffice -Times 1 -Exactly -ParameterFilter {
                $State -eq 'Disabled' -and $null -eq $StartTime -and $null -eq $EndTime
            }
        }
    }

    Context 'Batches of users' {
        It 'sets the auto-reply for every user in the batch' {
            $Result = Set-CIPPVacationOOO -TenantFilter 'contoso.com' -Action 'Add' `
                -Users @('one@contoso.com', 'two@contoso.com', 'three@contoso.com')

            Should -Invoke Set-CIPPOutOfOffice -Times 3 -Exactly
            $Result.Count | Should -Be 3
        }

        It 'carries on with the batch when one user fails' {
            Mock -CommandName Set-CIPPOutOfOffice -MockWith { throw 'Mailbox not found' } -ParameterFilter { $UserID -eq 'two@contoso.com' }

            $Result = Set-CIPPVacationOOO -TenantFilter 'contoso.com' -Action 'Add' `
                -Users @('one@contoso.com', 'two@contoso.com', 'three@contoso.com')

            Should -Invoke Set-CIPPOutOfOffice -Times 3 -Exactly
            $Result | Should -Contain 'Failed to set OOO for two@contoso.com: Mailbox not found'
            ($Result | Where-Object { $_ -eq 'Successfully set out of office' }).Count | Should -Be 2
        }

        It 'logs a failure against the tenant at Error severity' {
            Mock -CommandName Set-CIPPOutOfOffice -MockWith { throw 'Mailbox not found' }

            $null = Set-CIPPVacationOOO -TenantFilter 'contoso.com' -Action 'Add' -Users @('sseck@contoso.com')

            Should -Invoke Write-LogMessage -Times 1 -Exactly -ParameterFilter {
                $Sev -eq 'Error' -and $tenant -eq 'contoso.com' -and $message -like '*Failed OOO for sseck@contoso.com*'
            }
        }

        It 'ignores blank entries in the user list' {
            $null = Set-CIPPVacationOOO -TenantFilter 'contoso.com' -Action 'Add' -Users @('one@contoso.com', '', '   ', $null)

            Should -Invoke Set-CIPPOutOfOffice -Times 1 -Exactly
        }

        It 'does nothing when the user list is empty' {
            $Result = Set-CIPPVacationOOO -TenantFilter 'contoso.com' -Action 'Add' -Users @()

            Should -Invoke Set-CIPPOutOfOffice -Times 0 -Exactly
            $Result | Should -BeNullOrEmpty
        }
    }

    Context 'Guard rails' {
        It 'rejects an action other than Add or Remove' {
            { Set-CIPPVacationOOO -TenantFilter 'contoso.com' -Action 'Toggle' -Users @('sseck@contoso.com') } |
                Should -Throw
        }
    }
}
