# Pester tests for Get-CIPPUserOnboardingScan: the findings a returning user's account produces,
# and that one failing check never hides the others.

BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
    $Public = Join-Path $RepoRoot 'Modules/CIPPCore/Public'

    function New-GraphBulkRequest { param($tenantid, $Requests, $asapp) }
    function New-GraphGetRequest { param($uri, $tenantid, $scope, $extraHeaders, [switch]$UseCertificate, $AsApp) }
    function New-ExoBulkRequest { param($tenantid, $cmdletArray, $ReturnWithCommand, $Anchor) }
    function New-ExoRequest { param($tenantid, $cmdlet, $cmdParams, $anchor, $UseSystemMailbox, $Select) }
    function Resolve-CIPPFolderPermissionUser { param($TenantFilter, $FolderIdentity, $Permissions) }
    function Resolve-CIPPSharePointRestContext { param($TenantFilter, $SiteUrl) }
    function Get-ExoOnlineStringBytes { param($SizeString) }
    function Get-Tenants { param($TenantFilter) }
    function Get-CIPPTable { param($TableName) }
    function Get-CIPPAzDataTableEntity { param($Context, $Filter) }
    function ConvertTo-CIPPODataFilterValue { param($Value) $Value }
    function Get-CIPPPIMRoleAssignments { param($TenantFilter, $PrincipalId) }
    function Get-CippException { param($Exception) @{ NormalizedError = "$($Exception.Exception.Message)" } }
    function Write-LogMessage { param($headers, $API, $tenant, $message, $sev, $LogData) }
    function Write-Information { param($MessageData) }
    function Get-CippRequestAllowedPermissions { }

    . (Join-Path $Public 'BEC/Get-CIPPBecErrorInfo.ps1')
    . (Join-Path $Public 'Get-CIPPUserOnboardingScan.ps1')

    function New-TestSnapshotRow {
        [pscustomobject]@{
            OffboardedAt = '2026-09-12T08:00:00Z'
            Snapshot     = (@{
                    Licenses = @(@{ skuId = 'sku-1'; skuPartNumber = 'SPE_E3'; displayName = 'Microsoft 365 E3' })
                    Groups   = @(
                        @{ id = 'g-ok'; displayName = 'Sales'; groupType = 'Security' }
                        @{ id = 'g-dyn'; displayName = 'All staff'; groupType = 'Security' }
                        @{ id = 'g-sync'; displayName = 'AD group'; groupType = 'Security' }
                        @{ id = 'g-gone'; displayName = 'Old project'; groupType = 'Microsoft 365' }
                        @{ id = 'g-member'; displayName = 'Already in'; groupType = 'Security' }
                    )
                    Roles    = @(@{ id = 'role-1'; displayName = 'Helpdesk Administrator' })
                    Manager  = @{ id = 'm-1'; userPrincipalName = 'boss@contoso.com'; displayName = 'The Boss' }
                } | ConvertTo-Json -Depth 5 -Compress)
        }
    }
}

Describe 'Get-CIPPUserOnboardingScan' {
    BeforeEach {
        # Graph $batch replies by request id; anything not listed answers 200 with an empty collection.
        $script:Graph = @{
            user    = @{ status = 200; body = [pscustomobject]@{ id = 'u-1'; userPrincipalName = 'maria@contoso.com'; displayName = 'Maria Jensen'; accountEnabled = $false; onPremisesSyncEnabled = $null; onPremisesImmutableId = $null; assignedLicenses = @() } }
            skus    = @{ status = 200; body = [pscustomobject]@{ value = @([pscustomobject]@{ skuId = 'sku-1'; skuPartNumber = 'SPE_E3'; prepaidUnits = [pscustomobject]@{ enabled = 10 }; consumedUnits = 7 }) } }
            drive   = @{ status = 200; body = [pscustomobject]@{ sharepointIds = [pscustomobject]@{ siteUrl = 'https://contoso-my.sharepoint.com/personal/maria_contoso_com' } } }
            'g-ok'  = @{ status = 200; body = [pscustomobject]@{ id = 'g-ok'; displayName = 'Sales' } }
            'g-dyn' = @{ status = 200; body = [pscustomobject]@{ id = 'g-dyn'; displayName = 'All staff'; membershipRule = 'user.department -eq "x"' } }
            'g-sync' = @{ status = 200; body = [pscustomobject]@{ id = 'g-sync'; displayName = 'AD group'; onPremisesSyncEnabled = $true } }
            'g-gone' = @{ status = 404; body = [pscustomobject]@{ error = [pscustomobject]@{ message = 'not found' } } }
            'g-member' = @{ status = 200; body = [pscustomobject]@{ id = 'g-member'; displayName = 'Already in' } }
            '11111111-2222-3333-4444-555555555555' = @{ status = 200; body = [pscustomobject]@{ id = '11111111-2222-3333-4444-555555555555'; userPrincipalName = 'tom@contoso.com' } }
        }
        $script:Exo = @{
            'Get-Mailbox'                       = @([pscustomobject]@{ RecipientTypeDetails = 'SharedMailbox'; HiddenFromAddressListsEnabled = $true; ForwardingSmtpAddress = 'smtp:ext@fabrikam.com'; GrantSendOnBehalfTo = @('11111111-2222-3333-4444-555555555555') })
            'Get-MailboxAutoReplyConfiguration' = @([pscustomobject]@{ AutoReplyState = 'Enabled' })
            'Get-InboxRule'                     = @(
                [pscustomobject]@{ Name = 'Junk E-Mail Rule' }
                [pscustomobject]@{ Name = 'Send to gmail'; ForwardTo = @('x@gmail.com') }
                [pscustomobject]@{ Name = 'File newsletters' }
            )
            'Get-MailboxStatistics'             = @([pscustomobject]@{ TotalItemSize = '60 GB (64,424,509,440 bytes)' })
            'Get-MailboxPermission'             = @(
                [pscustomobject]@{ User = 'NT AUTHORITY\SELF'; AccessRights = @('FullAccess'); IsInherited = $false; Deny = $false }
                [pscustomobject]@{ User = 'tom@contoso.com'; AccessRights = @('FullAccess'); IsInherited = $false; Deny = $false }
            )
            'Get-RecipientPermission'           = @([pscustomobject]@{ Trustee = 'tom@contoso.com'; AccessRights = @('SendAs'); IsInherited = $false; AccessControlType = 'Allow' })
            'Get-MailboxFolderStatistics'       = @([pscustomobject]@{ Name = 'Kalender'; FolderType = 'Calendar' })
        }
        $script:SnapshotRow = $null

        Mock New-GraphBulkRequest {
            foreach ($Request in $Requests) {
                $Reply = $script:Graph[[string]$Request.id] ?? @{ status = 200; body = [pscustomobject]@{ value = @() } }
                [pscustomobject]@{ id = $Request.id; status = $Reply.status; body = $Reply.body }
            }
        }
        Mock New-ExoBulkRequest { $script:Exo }
        Mock New-ExoRequest {
            @(
                [pscustomobject]@{ User = 'Default'; AccessRights = @('AvailabilityOnly'); FolderName = 'Kalender' }
                [pscustomobject]@{ User = 'Tom Hansen'; AccessRights = @('Editor'); FolderName = 'Kalender' }
            )
        }
        Mock Resolve-CIPPFolderPermissionUser { foreach ($Permission in $Permissions) { $Permission | Add-Member -NotePropertyName UserId -NotePropertyValue 'tom-guid' -PassThru } }
        Mock Resolve-CIPPSharePointRestContext { @{ BaseUri = 'https://contoso-my.sharepoint.com/personal/maria_contoso_com/_api'; Scope = 'https://contoso-my.sharepoint.com/.default'; Headers = @{} } }
        Mock New-GraphGetRequest {
            @(
                [pscustomobject]@{ PrincipalType = 1; LoginName = 'i:0#.f|membership|maria@contoso.com' }
                [pscustomobject]@{ PrincipalType = 1; LoginName = 'i:0#.f|membership|boss@contoso.com' }
                [pscustomobject]@{ PrincipalType = 4; LoginName = 'c:0t.c|tenant|group' }
            )
        }
        Mock Get-ExoOnlineStringBytes { 64424509440 }
        Mock Get-Tenants { [pscustomobject]@{ customerId = 'cust-1' } }
        Mock Get-CIPPTable { @{ Context = 'ctx' } }
        Mock Get-CIPPAzDataTableEntity { $script:SnapshotRow }
        Mock Get-CIPPPIMRoleAssignments { @() }
        Mock Write-LogMessage { }
        Mock Write-Information { }
    }

    It 'returns the expected findings and fixes for a typical offboarded user' {
        $Scan = Get-CIPPUserOnboardingScan -TenantFilter 'contoso.com' -UserId 'maria@contoso.com'

        $Scan.Errors.Count | Should -Be 0
        $Scan.User.id | Should -Be 'u-1'
        $Scan.User.deleted | Should -BeFalse
        $Scan.Findings.Id | Should -Be @(
            'SignInBlocked', 'PasswordReset', 'TemporaryAccessPass', 'NoMfaMethods',
            'SharedMailbox', 'HiddenFromGAL', 'ForwardingSet', 'OutOfOfficeOn', 'InboxRules', 'SharedOverQuota',
            'MailboxDelegate:tom@contoso.com', 'CalendarDelegate:Tom Hansen', 'OneDriveSiteAdmin:boss@contoso.com',
            'NoLicenses', 'NoGroups', 'NoDevices'
        )
        $ByKey = @{}
        foreach ($Finding in $Scan.Findings) { $ByKey[$Finding.Id] = $Finding }
        $Scan.Findings.Where({ $_.Fix }).Fix.Key | Should -Be @(
            'EnableSignIn', 'ResetPassword', 'IssueTAP', 'ConvertToUserMailbox', 'UnhideFromGAL', 'RemoveForwarding', 'DisableOutOfOffice',
            'RemoveMailboxPermissions', 'RemoveCalendarPermissions', 'RemoveOneDriveSiteAdmins'
        )
        $ByKey['PasswordReset'].Fix.Default | Should -BeTrue
        $ByKey['TemporaryAccessPass'].Fix.Default | Should -BeFalse
        $ByKey['ForwardingSet'].Detail | Should -BeLike '*ext@fabrikam.com*'
        $ByKey['InboxRules'].Detail | Should -BeLike '*2 inbox rule(s)*Send to gmail*'
        $ByKey['InboxRules'].Note | Should -Be 'Report only'
        $ByKey['NoLicenses'].Note | Should -Be 'Next step'
        $ByKey['NoLicenses'].Fix | Should -BeNullOrEmpty

        # FullAccess, SendAs and the id-shaped SendOnBehalf entry collapse into one delegate
        $Delegate = $ByKey['MailboxDelegate:tom@contoso.com'].Fix.Params.Items[0]
        $Delegate.User | Should -Be 'tom@contoso.com'
        $Delegate.AccessRights | Should -Be @('FullAccess', 'SendAs', 'SendOnBehalf')
        $Calendar = $ByKey['CalendarDelegate:Tom Hansen'].Fix.Params.Items[0]
        $Calendar.User | Should -Be 'tom-guid'
        $Calendar.FolderName | Should -Be 'Kalender'
        $ByKey['OneDriveSiteAdmin:boss@contoso.com'].Fix.Params.Items[0].User | Should -Be 'boss@contoso.com'
    }

    It 'keeps the response shape through JSON at the depth the endpoint uses' {
        $Json = ConvertTo-Json -Depth 10 -InputObject @{ Results = (Get-CIPPUserOnboardingScan -TenantFilter 'contoso.com' -UserId 'u-1') } | ConvertFrom-Json

        $Json.Results.Snapshot | Should -BeNullOrEmpty
        $Json.Results.Errors.Count | Should -Be 0
        @(($Json.Results.Findings | Where-Object Id -EQ 'SignInBlocked').Fix.Params.PSObject.Properties).Count | Should -Be 0
        , ($Json.Results.Findings | Where-Object Id -Like 'MailboxDelegate:*').Fix.Params.Items | Should -BeOfType [array]
    }

    It 'does not default the password reset or enabling sign-in for an AD-synced user' {
        $script:Graph.user.body.onPremisesSyncEnabled = $true

        $Scan = Get-CIPPUserOnboardingScan -TenantFilter 'contoso.com' -UserId 'u-1'

        $Reset = $Scan.Findings | Where-Object Id -EQ 'PasswordReset'
        $Reset.Fix.Default | Should -BeFalse
        $Reset.Detail | Should -BeLike '*Active Directory*'
        $SignIn = $Scan.Findings | Where-Object Id -EQ 'SignInBlocked'
        $SignIn.Fix.Default | Should -BeFalse
        $SignIn.Detail | Should -BeLike '*Active Directory*'
        $Scan.Findings.Id | Should -Not -Contain 'ImmutableIdCleared'
    }

    It 'returns only SoftDeleted for a user found in deleted items' {
        $script:Graph.user = @{ status = 404; body = [pscustomobject]@{ error = [pscustomobject]@{ message = 'does not exist' } } }
        Mock New-GraphGetRequest {
            @(
                [pscustomobject]@{ id = 'other'; userPrincipalName = 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaasam@contoso.com' }
                [pscustomobject]@{ id = 'u-1'; displayName = 'Maria Jensen'; userPrincipalName = '0123456789abcdef0123456789abcdefmaria@contoso.com'; deletedDateTime = '2026-11-01T10:00:00Z' }
            )
        }

        $Scan = Get-CIPPUserOnboardingScan -TenantFilter 'contoso.com' -UserId 'maria@contoso.com'

        $Scan.Findings.Id | Should -Be @('SoftDeleted')
        $Scan.Findings[0].Fix.Key | Should -Be 'RestoreUser'
        $Scan.User.id | Should -Be 'u-1'
        $Scan.User.deleted | Should -BeTrue
        $Scan.User.userPrincipalName | Should -Be 'maria@contoso.com'
        $Scan.User.deletedDateTime | Should -Be '2026-11-01T10:00:00Z'
        $Scan.Snapshot | Should -BeNullOrEmpty
        Should -Invoke New-ExoBulkRequest -Times 0 -Exactly
    }

    It 'matches a deleted user on the whole UPN, never a longer one, and takes the latest deletion' {
        $script:Graph.user = @{ status = 404; body = [pscustomobject]@{ error = [pscustomobject]@{ message = 'does not exist' } } }
        Mock New-GraphGetRequest {
            @(
                [pscustomobject]@{ id = 'big'; displayName = 'Big John'; userPrincipalName = 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaabigjohn@contoso.com'; deletedDateTime = '2026-11-20T10:00:00Z' }
                [pscustomobject]@{ id = 'old'; displayName = 'John (2025)'; userPrincipalName = 'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbjohn@contoso.com'; deletedDateTime = '2025-03-01T10:00:00Z' }
                [pscustomobject]@{ id = 'new'; displayName = 'John'; userPrincipalName = 'ccccccccccccccccccccccccccccccccjohn@contoso.com'; deletedDateTime = '2026-11-01T10:00:00Z' }
            )
        }

        $Scan = Get-CIPPUserOnboardingScan -TenantFilter 'contoso.com' -UserId 'John@contoso.com'

        $Scan.User.id | Should -Be 'new'
        $Scan.User.userPrincipalName | Should -Be 'john@contoso.com'
    }

    It 'throws not-found when the user is in neither live nor deleted users' {
        $script:Graph.user = @{ status = 404; body = [pscustomobject]@{ error = [pscustomobject]@{ message = 'does not exist' } } }
        Mock New-GraphGetRequest { @() }

        { Get-CIPPUserOnboardingScan -TenantFilter 'contoso.com' -UserId 'nobody@contoso.com' } | Should -Throw -ExceptionType ([System.Management.Automation.ItemNotFoundException])
    }

    It 'reports NoMailbox as the only mailbox or mailbox-delegate finding when there is no mailbox' {
        $script:Exo = @{ 'Get-Mailbox' = @([pscustomobject]@{ error = "Ex6F9304|Microsoft.Exchange.Configuration.Tasks.ManagementObjectNotFoundException|The operation couldn't be performed because object 'maria@contoso.com' couldn't be found on 'x.PROD.OUTLOOK.COM'."; target = '' }) }

        $Scan = Get-CIPPUserOnboardingScan -TenantFilter 'contoso.com' -UserId 'u-1'

        $Scan.Errors.Count | Should -Be 0
        $Scan.Findings.Where({ $_.Category -eq 'Mailbox' }).Id | Should -Be @('NoMailbox')
        $Scan.Findings.Where({ $_.Id -like 'MailboxDelegate:*' -or $_.Id -like 'CalendarDelegate:*' }).Count | Should -Be 0
        Should -Invoke New-ExoRequest -Times 0 -Exactly
    }

    It 'puts one failing check in Errors and still returns the others' {
        $script:Exo['Get-InboxRule'] = @([pscustomobject]@{ error = 'The rules could not be read.'; target = '' })
        $script:Graph.devices = @{ status = 403; body = [pscustomobject]@{ error = [pscustomobject]@{ message = 'Insufficient privileges' } } }
        Mock Resolve-CIPPSharePointRestContext { throw 'SharePoint is unavailable' }

        $Scan = Get-CIPPUserOnboardingScan -TenantFilter 'contoso.com' -UserId 'u-1'

        $Scan.Errors.Check | Sort-Object | Should -Be @('Devices', 'Inbox rules', 'OneDrive access')
        ($Scan.Errors | Where-Object { $_.Check -eq 'Inbox rules' }).Message | Should -Be 'The rules could not be read.'
        $Scan.Findings.Id | Should -Not -Contain 'InboxRules'
        $Scan.Findings.Id | Should -Not -Contain 'NoDevices'
        $Scan.Findings.Id | Should -Contain 'SharedMailbox'
        $Scan.Findings.Id | Should -Contain 'MailboxDelegate:tom@contoso.com'
        $Scan.Findings.Id | Should -Contain 'NoGroups'
    }

    It 'names an internal forwarding target instead of showing its object id' {
        $script:Exo['Get-Mailbox'][0].ForwardingSmtpAddress = $null
        $script:Exo['Get-Mailbox'][0] | Add-Member -NotePropertyName ForwardingAddress -NotePropertyValue 'aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee' -Force
        Mock New-GraphGetRequest { [pscustomobject]@{ displayName = 'Grady Archie'; userPrincipalName = 'grady@contoso.com' } } -ParameterFilter { $uri -like '*/users/aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee*' }

        $Scan = Get-CIPPUserOnboardingScan -TenantFilter 'contoso.com' -UserId 'u-1'

        ($Scan.Findings | Where-Object Id -EQ 'ForwardingSet').Detail | Should -BeLike '*Grady Archie (grady@contoso.com)*'
    }

    It 'reports a locked OneDrive as a finding, not as a failed check' {
        Mock Resolve-CIPPSharePointRestContext { throw 'Access to this site has been blocked. Please contact the administrator to resolve this problem.' }

        $Scan = Get-CIPPUserOnboardingScan -TenantFilter 'contoso.com' -UserId 'u-1'

        ($Scan.Findings | Where-Object Id -EQ 'OneDriveLocked').Note | Should -Be 'Report only'
        $Scan.Errors.Check | Should -Not -Contain 'OneDrive access'

        # Graph can refuse the drive lookup itself with the same message.
        $script:Graph.drive = @{ status = 423; body = [pscustomobject]@{ error = [pscustomobject]@{ message = 'Access to this site has been blocked.' } } }
        $Scan = Get-CIPPUserOnboardingScan -TenantFilter 'contoso.com' -UserId 'u-1'
        $Scan.Findings.Id | Should -Contain 'OneDriveLocked'
        $Scan.Errors.Check | Should -Not -Contain 'OneDrive access'
    }

    It 'reports a failed mailbox read as an error, not as no mailbox' {
        Mock New-ExoBulkRequest { throw 'Exchange is unavailable' }

        $Scan = Get-CIPPUserOnboardingScan -TenantFilter 'contoso.com' -UserId 'u-1'

        $Scan.Errors.Check | Should -Be @('Mailbox')
        $Scan.Findings.Id | Should -Not -Contain 'NoMailbox'
        $Scan.Findings.Id | Should -Contain 'OneDriveSiteAdmin:boss@contoso.com'
    }

    It 'returns the snapshot with live licence availability and per-group restorability' {
        $script:SnapshotRow = New-TestSnapshotRow
        $script:Graph.groups = @{ status = 200; body = [pscustomobject]@{ value = @([pscustomobject]@{ id = 'g-member' }) } }

        $Scan = Get-CIPPUserOnboardingScan -TenantFilter 'contoso.com' -UserId 'u-1'

        Should -Invoke Get-CIPPAzDataTableEntity -Times 1 -Exactly -ParameterFilter { $Filter -eq "PartitionKey eq 'cust-1' and RowKey eq 'u-1'" }
        $Scan.Snapshot.OffboardedAt | Should -Be '2026-09-12T08:00:00Z'
        $Scan.Snapshot.Licenses[0].available | Should -Be 3
        $Scan.Snapshot.Manager.userPrincipalName | Should -Be 'boss@contoso.com'
        $Groups = @{}
        foreach ($Group in $Scan.Snapshot.Groups) { $Groups[$Group.id] = $Group }
        $Groups['g-ok'].restorable | Should -BeTrue
        $Groups['g-ok'].skipReason | Should -BeNullOrEmpty
        $Groups['g-dyn'].restorable | Should -BeFalse
        $Groups['g-dyn'].skipReason | Should -BeLike '*dynamic*'
        $Groups['g-sync'].skipReason | Should -BeLike '*Active Directory*'
        $Groups['g-gone'].skipReason | Should -BeLike '*deleted*'
        $Groups['g-member'].skipReason | Should -BeLike '*already a member*'
        $Scan.Findings.Id | Should -Not -Contain 'NoGroups'

        $Roles = $Scan.Findings | Where-Object Id -EQ 'RolesRemoved'
        $Roles.Detail | Should -BeLike '*Helpdesk Administrator*'
        $Roles.Fix | Should -BeNullOrEmpty
    }

    It 'offers a group that grants admin roles only to a caller who can manage privileged users' {
        $script:SnapshotRow = New-TestSnapshotRow
        $script:Graph['g-ok'].body = [pscustomobject]@{ id = 'g-ok'; displayName = 'Sales'; isAssignableToRole = $true }

        Mock Get-CippRequestAllowedPermissions { , @('Identity.User.ReadWrite') }
        $Restricted = (Get-CIPPUserOnboardingScan -TenantFilter 'contoso.com' -UserId 'u-1').Snapshot.Groups | Where-Object id -EQ 'g-ok'
        $Restricted.restorable | Should -BeFalse
        $Restricted.skipReason | Should -BeLike '*Identity.PrivilegedUser.ReadWrite*'

        Mock Get-CippRequestAllowedPermissions { , @('Identity.User.ReadWrite', 'Identity.PrivilegedUser.ReadWrite') }
        ((Get-CIPPUserOnboardingScan -TenantFilter 'contoso.com' -UserId 'u-1').Snapshot.Groups | Where-Object id -EQ 'g-ok').restorable | Should -BeTrue
    }

    It 'reports a cleared immutable ID only when the snapshot recorded one' {
        $script:SnapshotRow = New-TestSnapshotRow
        (Get-CIPPUserOnboardingScan -TenantFilter 'contoso.com' -UserId 'u-1').Findings.Id | Should -Not -Contain 'ImmutableIdCleared'

        $Saved = $script:SnapshotRow.Snapshot | ConvertFrom-Json
        $Saved | Add-Member -NotePropertyName HadImmutableId -NotePropertyValue $true
        $script:SnapshotRow.Snapshot = $Saved | ConvertTo-Json -Depth 5 -Compress
        $Finding = (Get-CIPPUserOnboardingScan -TenantFilter 'contoso.com' -UserId 'u-1').Findings | Where-Object Id -EQ 'ImmutableIdCleared'
        $Finding.Note | Should -Be 'Report only'
    }

    It 'does not report RolesRemoved for a role the user still holds' {
        $script:SnapshotRow = New-TestSnapshotRow
        Mock Get-CIPPPIMRoleAssignments { [pscustomobject]@{ RoleDefinitionId = 'role-1' } }

        $Scan = Get-CIPPUserOnboardingScan -TenantFilter 'contoso.com' -UserId 'u-1'

        $Scan.Findings.Id | Should -Not -Contain 'RolesRemoved'
    }
}
