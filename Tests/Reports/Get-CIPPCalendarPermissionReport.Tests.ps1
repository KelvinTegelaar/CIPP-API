# Pester tests for the grantee scope in Get-CIPPCalendarPermissionReport. Cached grantees are the
# plain strings Exchange returns: internal recipients by display name, external shares by address,
# and calendars shared with a consumer address as 'ExchangePublishedUser.<address>'.

BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
    $FunctionPath = Get-ChildItem -Path (Join-Path $RepoRoot 'Modules') -Recurse -Filter 'Get-CIPPCalendarPermissionReport.ps1' -File -ErrorAction SilentlyContinue |
        Select-Object -First 1 -ExpandProperty FullName
    if (-not $FunctionPath) { throw 'Could not locate Get-CIPPCalendarPermissionReport.ps1 under Modules/' }

    function Get-CIPPDbItem { param($TenantFilter, $Type, [switch]$CountsOnly, [switch]$ByTenant) }
    function Write-LogMessage { param($headers, $API, $tenant, $message, $sev, $LogData) }
    function Get-CippException { param($Exception) }

    . $FunctionPath

    $Stamp = [datetime]'2026-11-20T10:00:00Z'
    $script:Mailboxes = @(
        [pscustomobject]@{ RowKey = 'm1'; Timestamp = $Stamp; Data = '{"UPN":"owner@contoso.com","primarySmtpAddress":"owner@contoso.com","displayName":"Owner","recipientTypeDetails":"UserMailbox","Id":"1","ExternalDirectoryObjectId":"1"}' }
        [pscustomobject]@{ RowKey = 'm2'; Timestamp = $Stamp; Data = '{"UPN":"other@contoso.com","primarySmtpAddress":"other@contoso.com","displayName":"Other","recipientTypeDetails":"UserMailbox","Id":"2","ExternalDirectoryObjectId":"2"}' }
    )
    $script:Permissions = @(
        [pscustomobject]@{ RowKey = 'p1'; Timestamp = $Stamp; Data = '{"Identity":"owner@contoso.com:\\Calendar","User":"Default","AccessRights":["LimitedDetails"],"FolderName":"Calendar"}' }
        [pscustomobject]@{ RowKey = 'p2'; Timestamp = $Stamp; Data = '{"Identity":"owner@contoso.com:\\Calendar","User":"Assistant One","AccessRights":["Editor"],"FolderName":"Calendar"}' }
        [pscustomobject]@{ RowKey = 'p3'; Timestamp = $Stamp; Data = '{"Identity":"owner@contoso.com:\\Calendar","User":"socials@fabrikam.com","AccessRights":["Reviewer"],"FolderName":"Calendar"}' }
        [pscustomobject]@{ RowKey = 'p4'; Timestamp = $Stamp; Data = '{"Identity":"owner@contoso.com:\\Calendar","User":"ExchangePublishedUser.friend@gmail.com","AccessRights":["Reviewer"],"FolderName":"Calendar"}' }
        [pscustomobject]@{ RowKey = 'p5'; Timestamp = $Stamp; Data = '{"Identity":"other@contoso.com:\\Calendar","User":"Assistant One","AccessRights":["Reviewer"],"FolderName":"Calendar"}' }
    )
}

Describe 'Get-CIPPCalendarPermissionReport grantee scope' {
    BeforeAll {
        Mock Get-CIPPDbItem -ParameterFilter { $Type -eq 'Mailboxes' } { $script:Mailboxes }
        Mock Get-CIPPDbItem -ParameterFilter { $Type -eq 'CalendarPermissions' } { $script:Permissions }
    }

    Context 'By calendar' {
        BeforeAll {
            $script:ByCalendar = @{}
            foreach ($Row in Get-CIPPCalendarPermissionReport -TenantFilter 'contoso.com') { $script:ByCalendar[$Row.CalendarUPN] = $Row }
        }

        It 'flags a calendar with an external grantee as shared externally' {
            $script:ByCalendar['owner@contoso.com'].SharedExternally | Should -BeTrue
        }

        It 'does not flag a calendar shared only internally' {
            $script:ByCalendar['other@contoso.com'].SharedExternally | Should -BeFalse
        }

        It 'labels each grant and gives the external address' {
            $Grants = @{}
            foreach ($Grant in $script:ByCalendar['owner@contoso.com'].Permissions) { $Grants[$Grant.User] = $Grant }

            $Grants['Assistant One'].AccessScope | Should -Be 'Internal'
            $Grants['socials@fabrikam.com'].AccessScope | Should -Be 'External'
            $Grants['socials@fabrikam.com'].ExternalAddress | Should -Be 'socials@fabrikam.com'
            $Grants['ExchangePublishedUser.friend@gmail.com'].AccessScope | Should -Be 'External (published link)'
            $Grants['ExchangePublishedUser.friend@gmail.com'].ExternalAddress | Should -Be 'friend@gmail.com'
        }

        It 'still leaves out the Default entry' {
            $script:ByCalendar['owner@contoso.com'].Permissions.User | Should -Not -Contain 'Default'
        }
    }

    Context 'By user' {
        BeforeAll {
            $script:ByUser = @{}
            foreach ($Row in Get-CIPPCalendarPermissionReport -TenantFilter 'contoso.com' -ByUser) { $script:ByUser[$Row.User] = $Row }
        }

        It 'labels each grantee' {
            $script:ByUser['Assistant One'].AccessScope | Should -Be 'Internal'
            $script:ByUser['Assistant One'].CalendarCount | Should -Be 2
            $script:ByUser['socials@fabrikam.com'].AccessScope | Should -Be 'External'
            $script:ByUser['ExchangePublishedUser.friend@gmail.com'].AccessScope | Should -Be 'External (published link)'
            $script:ByUser['ExchangePublishedUser.friend@gmail.com'].ExternalAddress | Should -Be 'friend@gmail.com'
        }
    }
}
