# Pester tests for New-CIPPPIMScheduleRequest - the only builder of PIM schedule request bodies.
#
# The security rule these tests pin down: CIPP never creates a permanent (no-expiration) role
# assignment or eligibility. Every caller - endpoint, standard, scheduled task - goes through this
# function, so "it refuses to build without an expiration" is the whole guarantee.

BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
    . (Join-Path $RepoRoot 'Modules/CIPPCore/Public/PIM/New-CIPPPIMScheduleRequest.ps1')

    $script:Common = @{
        PrincipalId      = 'aaaaaaaa-0000-0000-0000-000000000001'
        RoleDefinitionId = '62e90394-69f5-4237-9190-012177145e10'
        Justification    = 'Ticket 1234'
    }
}

Describe 'New-CIPPPIMScheduleRequest' {
    Context 'refuses permanent / no-expiration input' {
        It 'throws when neither Duration nor EndDateTime is given for <_>' -ForEach @('adminAssign', 'adminUpdate', 'adminExtend', 'adminRenew') {
            { New-CIPPPIMScheduleRequest -Kind Assignment -Action $_ @script:Common } | Should -Throw '*never creates permanent*'
            { New-CIPPPIMScheduleRequest -Kind Eligibility -Action $_ @script:Common } | Should -Throw '*never creates permanent*'
        }

        It 'throws when the duration asks for permanence by name: <_>' -ForEach @('noExpiration', 'permanent', 'never', 'unlimited', 'none', ' NoExpiration ') {
            { New-CIPPPIMScheduleRequest -Kind Eligibility -Action adminAssign -Duration $_ @script:Common } | Should -Throw '*permanent (no-expiration)*'
        }

        It 'throws on a duration that is not ISO 8601' {
            { New-CIPPPIMScheduleRequest -Kind Assignment -Action adminAssign -Duration '8 hours' @script:Common } | Should -Throw '*not a valid ISO 8601 duration*'
        }

        It 'throws on a zero-length duration' {
            { New-CIPPPIMScheduleRequest -Kind Assignment -Action adminAssign -Duration 'PT0S' @script:Common } | Should -Throw '*greater than zero*'
        }

        It 'throws when EndDateTime is in the past' {
            { New-CIPPPIMScheduleRequest -Kind Assignment -Action adminAssign -EndDateTime ([datetime]::UtcNow.AddHours(-1)) @script:Common } | Should -Throw '*not in the future*'
        }

        It 'throws when both Duration and EndDateTime are given' {
            { New-CIPPPIMScheduleRequest -Kind Assignment -Action adminAssign -Duration 'PT1H' -EndDateTime ([datetime]::UtcNow.AddHours(2)) @script:Common } | Should -Throw '*not both*'
        }

        It 'throws when a duration exceeds MaxDuration instead of clamping it' {
            { New-CIPPPIMScheduleRequest -Kind Assignment -Action adminAssign -Duration 'PT10H' -MaxDuration 'PT8H' @script:Common } | Should -Throw '*exceeds the maximum allowed*'
        }

        It 'throws when an end date exceeds MaxDuration instead of clamping it' {
            { New-CIPPPIMScheduleRequest -Kind Eligibility -Action adminAssign -EndDateTime ([datetime]::UtcNow.AddDays(400)) -MaxDuration 'P365D' @script:Common } | Should -Throw '*exceeds the maximum allowed*'
        }

        It 'throws on an invalid MaxDuration rather than ignoring the cap' {
            { New-CIPPPIMScheduleRequest -Kind Assignment -Action adminAssign -Duration 'PT1H' -MaxDuration 'forever' @script:Common } | Should -Throw '*MaxDuration*'
        }
    }

    Context 'builds valid time-bound bodies' {
        It 'emits an afterDuration expiration for a duration' {
            $Request = New-CIPPPIMScheduleRequest -Kind Assignment -Action adminAssign -Duration 'PT4H' -MaxDuration 'PT8H' @script:Common

            $Request.Uri | Should -Be 'https://graph.microsoft.com/v1.0/roleManagement/directory/roleAssignmentScheduleRequests'
            $Request.Body.action | Should -Be 'adminAssign'
            $Request.Body.principalId | Should -Be $script:Common.PrincipalId
            $Request.Body.roleDefinitionId | Should -Be $script:Common.RoleDefinitionId
            $Request.Body.directoryScopeId | Should -Be '/'
            $Request.Body.justification | Should -Be 'Ticket 1234'
            $Request.Body.scheduleInfo.expiration.type | Should -Be 'afterDuration'
            $Request.Body.scheduleInfo.expiration.duration | Should -Be 'PT4H'
            $Request.ExpirationType | Should -Be 'afterDuration'
            ($Request.EndDateTime - [datetime]::UtcNow).TotalHours | Should -BeGreaterThan 3.9
            ($Request.EndDateTime - [datetime]::UtcNow).TotalHours | Should -BeLessThan 4.1
        }

        It 'emits an afterDateTime expiration for an end date, in UTC' {
            $End = [datetime]::UtcNow.AddDays(30)
            $Request = New-CIPPPIMScheduleRequest -Kind Eligibility -Action adminAssign -EndDateTime $End -MaxDuration 'P365D' @script:Common

            $Request.Uri | Should -Be 'https://graph.microsoft.com/v1.0/roleManagement/directory/roleEligibilityScheduleRequests'
            $Request.Body.scheduleInfo.expiration.type | Should -Be 'afterDateTime'
            $Request.Body.scheduleInfo.expiration.endDateTime | Should -Match '^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}Z$'
            $Request.Body.scheduleInfo.startDateTime | Should -Match 'Z$'
            $Request.EndDateTime | Should -Be $End
        }

        It 'accepts a year-long eligibility within the P365D cap' {
            $Request = New-CIPPPIMScheduleRequest -Kind Eligibility -Action adminAssign -Duration 'P1Y' -MaxDuration 'P365D' @script:Common
            $Request.Body.scheduleInfo.expiration.duration | Should -Be 'P1Y'
        }

        It 'uses the explicit scope and start when given' {
            $Start = [datetime]::UtcNow.AddHours(1)
            $Request = New-CIPPPIMScheduleRequest -Kind Assignment -Action adminAssign -Duration 'PT1H' -StartDateTime $Start -DirectoryScopeId '/administrativeUnits/abc' @script:Common
            $Request.Body.directoryScopeId | Should -Be '/administrativeUnits/abc'
            $Request.StartDateTime | Should -Be $Start
        }

        It 'adds ticketInfo when a ticket is supplied' {
            $Request = New-CIPPPIMScheduleRequest -Kind Assignment -Action adminExtend -Duration 'PT2H' -TicketNumber 'INC-1' -TicketSystem 'Halo' @script:Common
            $Request.Body.ticketInfo.ticketNumber | Should -Be 'INC-1'
            $Request.Body.ticketInfo.ticketSystem | Should -Be 'Halo'
        }

        It 'never emits noExpiration for any schedule-creating action' -ForEach @('adminAssign', 'adminUpdate', 'adminExtend', 'adminRenew') {
            $Request = New-CIPPPIMScheduleRequest -Kind Assignment -Action $_ -Duration 'PT1H' @script:Common
            (ConvertTo-Json -InputObject $Request.Body -Depth 10 -Compress) | Should -Not -Match 'noExpiration'
            $Request.Body.scheduleInfo.expiration.type | Should -BeIn @('afterDuration', 'afterDateTime')
        }
    }

    Context 'adminRemove' {
        It 'needs no schedule and carries no expiration' {
            $Request = New-CIPPPIMScheduleRequest -Kind Eligibility -Action adminRemove @script:Common
            $Request.Body.action | Should -Be 'adminRemove'
            $Request.Body.Contains('scheduleInfo') | Should -BeFalse
            $Request.EndDateTime | Should -BeNullOrEmpty
            $Request.ExpirationType | Should -BeNullOrEmpty
        }
    }
}
