BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))

    class HttpResponseContext {
        [object]$StatusCode
        [object]$Body
    }
    $Accelerators = [PSObject].Assembly.GetType('System.Management.Automation.TypeAccelerators')
    if (-not ('HttpStatusCode' -as [type])) {
        $Accelerators::Add('HttpStatusCode', [System.Net.HttpStatusCode])
    }

    function New-GraphGetRequest { param($uri, $tenantid, [switch]$ComplexFilter) }
    function New-ExoRequest { param($tenantid, $cmdlet, $cmdParams, $Select) }
    function New-GraphBulkRequest { param($tenantid, $Requests, $Version, $MaxConcurrency) }
    function New-ExoBulkRequest { param($tenantid, $cmdletArray, $useSystemMailbox, $MaxConcurrency) }
    function Assert-CippPrivilegedUserAccess { param($TenantFilter, $UserId, [switch]$PassThru) }
    function Write-LogMessage { param($headers, $API, $tenant, $message, $Sev, $LogData) }
    function Get-CippException { param($Exception) [pscustomobject]@{ NormalizedError = $Exception.Exception.Message } }
    function Get-NormalizedError { param($Message) $Message }

    . (Join-Path $RepoRoot 'Modules/CIPPHTTP/Public/Entrypoints/HTTP Functions/Tenant/Tools/Invoke-ExecEmailDomainMigration.ps1')
    . (Join-Path $RepoRoot 'Modules/CIPPCore/Public/Get-CippErrorStatusCode.ps1')
    . (Join-Path $RepoRoot 'Modules/CIPPCore/Public/Get-CippBulkStatusCode.ps1')

    function New-MigrationRequest([hashtable]$Body) {
        $Defaults = @{ tenantFilter = 'contoso.com'; SourceDomain = 'old.com'; TargetDomain = 'new.com' }
        foreach ($Key in $Body.Keys) { $Defaults[$Key] = $Body[$Key] }
        [pscustomobject]@{ Body = [pscustomobject]$Defaults; Headers = @{}; Params = @{ CIPPEndpoint = 'ExecEmailDomainMigration' }; Query = @{} }
    }
    function Get-Row($Response, $Id) { @($Response.Body.Results).Where({ $_.id -eq $Id }, 'First')[0] }

    $script:GraphUsers = @(
        [pscustomobject]@{ id = 'alice'; displayName = 'Alice'; userPrincipalName = 'alice@old.com'; userType = 'Member'; onPremisesSyncEnabled = $null }
        [pscustomobject]@{ id = 'bob'; displayName = 'Bob'; userPrincipalName = 'bob@old.com'; userType = 'Member'; onPremisesSyncEnabled = $true }
        [pscustomobject]@{ id = 'carol'; displayName = 'Carol'; userPrincipalName = 'carol@old.com'; userType = 'Member'; onPremisesSyncEnabled = $null }
        [pscustomobject]@{ id = 'shared'; displayName = 'Sales Shared'; userPrincipalName = 'shared@old.com'; userType = 'Member'; onPremisesSyncEnabled = $null }
        [pscustomobject]@{ id = 'guest'; displayName = 'Guest'; userPrincipalName = 'g_ext#EXT#@old.com'; userType = 'Guest'; onPremisesSyncEnabled = $null }
        [pscustomobject]@{ id = 'erin'; displayName = 'Erin'; userPrincipalName = 'erin@old.com'; userType = 'Member'; onPremisesSyncEnabled = $null }
        [pscustomobject]@{ id = 'nomail'; displayName = 'No Mail'; userPrincipalName = 'nomail@old.com'; userType = 'Member'; onPremisesSyncEnabled = $null }
        [pscustomobject]@{ id = 'carol2'; displayName = 'Carol Two'; userPrincipalName = 'carol@new.com'; userType = 'Member'; onPremisesSyncEnabled = $null }
        [pscustomobject]@{ id = 'frank'; displayName = 'Frank'; userPrincipalName = 'frank@old.com'; userType = 'Member'; onPremisesSyncEnabled = $null }
        [pscustomobject]@{ id = 'gina'; displayName = 'Gina'; userPrincipalName = 'gina@old.com'; userType = 'Member'; onPremisesSyncEnabled = $null }
    )
    $script:Recipients = @(
        [pscustomobject]@{ ExternalDirectoryObjectId = 'alice'; Guid = 'g-alice'; DisplayName = 'Alice'; WindowsLiveID = 'alice@old.com'; PrimarySmtpAddress = 'alice@old.com'; EmailAddresses = @('SMTP:alice@old.com', 'smtp:alice@old.onmicrosoft.com'); RecipientTypeDetails = 'UserMailbox'; IsDirSynced = $false }
        [pscustomobject]@{ ExternalDirectoryObjectId = 'bob'; Guid = 'g-bob'; DisplayName = 'Bob'; WindowsLiveID = 'bob@old.com'; PrimarySmtpAddress = 'bob@old.com'; EmailAddresses = @('SMTP:bob@old.com'); RecipientTypeDetails = 'UserMailbox'; IsDirSynced = $true }
        [pscustomobject]@{ ExternalDirectoryObjectId = 'carol'; Guid = 'g-carol'; DisplayName = 'Carol'; WindowsLiveID = 'carol@old.com'; PrimarySmtpAddress = 'carol@old.com'; EmailAddresses = @('SMTP:carol@old.com'); RecipientTypeDetails = 'UserMailbox'; IsDirSynced = $false }
        [pscustomobject]@{ ExternalDirectoryObjectId = 'shared'; Guid = 'g-shared'; DisplayName = 'Sales Shared'; WindowsLiveID = 'shared@old.com'; PrimarySmtpAddress = 'shared@old.com'; EmailAddresses = @('SMTP:shared@old.com'); RecipientTypeDetails = 'SharedMailbox'; IsDirSynced = $false }
        [pscustomobject]@{ ExternalDirectoryObjectId = 'erin'; Guid = 'g-erin'; DisplayName = 'Erin'; WindowsLiveID = 'erin@old.com'; PrimarySmtpAddress = 'erin@old.com'; EmailAddresses = @('SMTP:erin@old.com', 'smtp:er%tenantid%in@old.com'); RecipientTypeDetails = 'UserMailbox'; IsDirSynced = $false }
        [pscustomobject]@{ ExternalDirectoryObjectId = 'frank'; Guid = 'g-frank'; DisplayName = 'Frank'; WindowsLiveID = 'frank@old.com'; PrimarySmtpAddress = 'f.smith@old.com'; EmailAddresses = @('SMTP:f.smith@old.com', 'smtp:Frank@old.com', 'smtp:frank@old.onmicrosoft.com'); RecipientTypeDetails = 'UserMailbox'; IsDirSynced = $false }
        [pscustomobject]@{ ExternalDirectoryObjectId = 'gina'; Guid = 'g-gina'; DisplayName = 'Gina'; WindowsLiveID = 'gina@old.com'; PrimarySmtpAddress = 'gina@pending.com'; EmailAddresses = @('SMTP:gina@pending.com'); RecipientTypeDetails = 'UserMailbox'; IsDirSynced = $false }
        [pscustomobject]@{ ExternalDirectoryObjectId = 'dave'; Guid = 'g-dave'; DisplayName = 'Dave'; WindowsLiveID = 'dave@other.com'; PrimarySmtpAddress = 'dave@old.com'; EmailAddresses = @('SMTP:dave@old.com'); RecipientTypeDetails = 'UserMailbox'; IsDirSynced = $false }
        [pscustomobject]@{ ExternalDirectoryObjectId = 'room'; Guid = 'g-room'; DisplayName = 'Room'; WindowsLiveID = 'room@old.com'; PrimarySmtpAddress = 'room@old.com'; EmailAddresses = @('SMTP:room@old.com'); RecipientTypeDetails = 'RoomMailbox'; IsDirSynced = $false }
        [pscustomobject]@{ ExternalDirectoryObjectId = 'group'; Guid = 'g-group'; DisplayName = 'Sales'; WindowsLiveID = ''; PrimarySmtpAddress = 'dave@new.com'; EmailAddresses = @('SMTP:dave@new.com', 'smtp:help@new.com'); RecipientTypeDetails = 'GroupMailbox'; IsDirSynced = $false }
        [pscustomobject]@{ ExternalDirectoryObjectId = 'm365'; Guid = 'g-m365'; DisplayName = 'Team'; WindowsLiveID = ''; PrimarySmtpAddress = 'team@old.com'; EmailAddresses = @('SPO:SPO_1@SPO_2', 'SMTP:team@old.com', 'smtp:team@old.onmicrosoft.com'); RecipientTypeDetails = 'GroupMailbox'; IsDirSynced = $false }
        [pscustomobject]@{ ExternalDirectoryObjectId = 'dl'; Guid = 'g-dl'; DisplayName = 'Sales DL'; WindowsLiveID = ''; PrimarySmtpAddress = 'salesdl@old.com'; EmailAddresses = @('SMTP:salesdl@old.com', 'X500:/o=x/cn=salesdl'); RecipientTypeDetails = 'MailUniversalDistributionGroup'; IsDirSynced = $false }
        [pscustomobject]@{ ExternalDirectoryObjectId = ''; Guid = 'g-ddg'; DisplayName = 'Everyone'; WindowsLiveID = ''; PrimarySmtpAddress = 'everyone@old.com'; EmailAddresses = @('SMTP:everyone@old.com'); RecipientTypeDetails = 'DynamicDistributionGroup'; IsDirSynced = $false }
        [pscustomobject]@{ ExternalDirectoryObjectId = 'sec'; Guid = 'g-sec'; DisplayName = 'Synced Sec'; WindowsLiveID = ''; PrimarySmtpAddress = 'sec@old.com'; EmailAddresses = @('SMTP:sec@old.com'); RecipientTypeDetails = 'MailUniversalSecurityGroup'; IsDirSynced = $true }
        [pscustomobject]@{ ExternalDirectoryObjectId = 'help'; Guid = 'g-help'; DisplayName = 'Help'; WindowsLiveID = ''; PrimarySmtpAddress = 'help@old.com'; EmailAddresses = @('SMTP:help@old.com'); RecipientTypeDetails = 'MailNonUniversalGroup'; IsDirSynced = $false }
    )
    $script:SyncedGroups = @([pscustomobject]@{ id = 'sec' })
    function Get-RecipientsWith([string[]]$Ids, [hashtable]$Set) {
        foreach ($R in $script:Recipients) {
            if ($R.ExternalDirectoryObjectId -notin $Ids) { $R; continue }
            $Copy = $R.PSObject.Copy()
            foreach ($Key in $Set.Keys) { $Copy | Add-Member -NotePropertyName $Key -NotePropertyValue $Set[$Key] -Force }
            $Copy
        }
    }
}

Describe 'Invoke-ExecEmailDomainMigration' {
    BeforeEach {
        $script:FailUpn = @()
        $script:FailMailbox = @()
        Mock Write-LogMessage { }
        Mock Assert-CippPrivilegedUserAccess { }
        Mock New-GraphGetRequest {
            if ($uri -like '*/domains*') {
                @(
                    [pscustomobject]@{ id = 'old.com'; isVerified = $true }
                    [pscustomobject]@{ id = 'new.com'; isVerified = $true }
                    [pscustomobject]@{ id = 'pending.com'; isVerified = $false }
                )
            } elseif ($uri -like '*/users?$filter=onPremisesSyncEnabled*') {
                @($script:GraphUsers).Where({ $_.onPremisesSyncEnabled -eq $true })
            } elseif ($uri -like '*/groups?$filter=onPremisesSyncEnabled*') {
                $script:SyncedGroups
            } else { $script:GraphUsers }
        }
        Mock New-ExoRequest { $script:Recipients }
        Mock New-GraphBulkRequest {
            foreach ($R in $Requests) {
                if ($R.id -in $script:FailUpn) {
                    [pscustomobject]@{ id = $R.id; status = 400; body = [pscustomobject]@{ error = [pscustomobject]@{ message = 'UPN rejected' } } }
                } else {
                    [pscustomobject]@{ id = $R.id; status = 204 }
                }
            }
        }
        Mock New-ExoBulkRequest {
            $script:ExoSent = @($cmdletArray)
            foreach ($C in $cmdletArray) {
                if ($C.OperationGuid -in $script:FailMailbox) {
                    [pscustomobject]@{ error = 'Proxy address rejected'; OperationGuid = $C.OperationGuid }
                } else {
                    [pscustomobject]@{ Success = $true; OperationGuid = $C.OperationGuid }
                }
            }
        }
    }

    Context 'validation' {
        It 'returns 400 when <Case>' -TestCases @(
            @{ Case = 'no tenant is chosen'; Body = @{ tenantFilter = $null; Preview = $true } }
            @{ Case = 'All Tenants is chosen'; Body = @{ tenantFilter = 'AllTenants'; Preview = $true } }
            @{ Case = 'a domain is missing'; Body = @{ TargetDomain = ''; Preview = $true } }
            @{ Case = 'a domain is not a domain name'; Body = @{ SourceDomain = "old.com') or (1 eq 1"; Preview = $true } }
            @{ Case = 'both domains are the same'; Body = @{ TargetDomain = 'OLD.com'; Preview = $true } }
            @{ Case = 'no users are chosen'; Body = @{ } }
            @{ Case = 'over 500 users are chosen'; Body = @{ Users = @(1..501 | ForEach-Object { "user$_" }) } }
        ) {
            $Response = Invoke-ExecEmailDomainMigration -Request (New-MigrationRequest $Body)
            $Response.StatusCode | Should -Be ([System.Net.HttpStatusCode]::BadRequest)
            Should -Invoke New-GraphGetRequest -Times 0
        }

        It 'returns 400 when the target domain is not verified' {
            $Response = Invoke-ExecEmailDomainMigration -Request (New-MigrationRequest @{ TargetDomain = 'pending.com'; Preview = $true })
            $Response.StatusCode | Should -Be ([System.Net.HttpStatusCode]::BadRequest)
            $Response.Body.Results | Should -BeLike '*pending.com is not a verified domain*'
        }

        It 'returns 500 when Exchange cannot be read' {
            Mock New-ExoRequest { throw 'Exchange is down' }
            $Response = Invoke-ExecEmailDomainMigration -Request (New-MigrationRequest @{ Preview = $true })
            $Response.StatusCode | Should -Be ([System.Net.HttpStatusCode]::InternalServerError)
        }
    }

    Context 'preview' {
        It 'plans old -> new per user and writes nothing' {
            $Response = Invoke-ExecEmailDomainMigration -Request (New-MigrationRequest @{ Preview = $true })
            $Response.StatusCode | Should -Be ([System.Net.HttpStatusCode]::OK)
            $Alice = Get-Row $Response 'alice'
            $Alice.status | Should -Be 'Ready'
            $Alice.newUserPrincipalName | Should -Be 'alice@new.com'
            $Alice.newPrimarySmtpAddress | Should -Be 'alice@new.com'
            $NoMail = Get-Row $Response 'nomail'
            $NoMail.newUserPrincipalName | Should -Be 'nomail@new.com'
            $NoMail.newPrimarySmtpAddress | Should -BeNullOrEmpty
            $Dave = Get-Row $Response 'dave'
            $Dave.userPrincipalName | Should -Be 'dave@other.com'
            $Dave.newUserPrincipalName | Should -BeNullOrEmpty
            Should -Invoke New-GraphBulkRequest -Times 0
            Should -Invoke New-ExoBulkRequest -Times 0
        }

        It 'skips synced users with the reason' {
            $Bob = Get-Row (Invoke-ExecEmailDomainMigration -Request (New-MigrationRequest @{ Preview = $true })) 'bob'
            $Bob.status | Should -Be 'Skipped'
            $Bob.reason | Should -BeLike 'Synced from on-premises*'
        }

        It 'skips users whose new address is already taken, by a user or a group' {
            $Response = Invoke-ExecEmailDomainMigration -Request (New-MigrationRequest @{ Preview = $true })
            (Get-Row $Response 'carol').reason | Should -Be 'carol@new.com is already used by another user, group or contact.'
            (Get-Row $Response 'dave').reason | Should -Be 'dave@new.com is already used by another user, group or contact.'
        }

        It 'keeps users whose new address is taken when the collision check is off' {
            $Carol = Get-Row (Invoke-ExecEmailDomainMigration -Request (New-MigrationRequest @{ Preview = $true; SkipCollisions = $false })) 'carol'
            $Carol.status | Should -Be 'Ready'
        }

        It 'skips a mailbox with a % in an address, which the Exchange helper would expand' {
            (Get-Row (Invoke-ExecEmailDomainMigration -Request (New-MigrationRequest @{ Preview = $true })) 'erin').reason | Should -BeLike '*% sign*'
        }

        It 'lists shared mailboxes only when asked, and never guests or rooms' {
            $Default = Invoke-ExecEmailDomainMigration -Request (New-MigrationRequest @{ Preview = $true })
            @($Default.Body.Results.id) | Should -Not -Contain 'shared'
            @($Default.Body.Results.id) | Should -Not -Contain 'guest'
            @($Default.Body.Results.id) | Should -Not -Contain 'room'
            $Shared = Get-Row (Invoke-ExecEmailDomainMigration -Request (New-MigrationRequest @{ Preview = $true; IncludeSharedMailboxes = $true })) 'shared'
            $Shared.type | Should -Be 'Shared mailbox'
            $Shared.status | Should -Be 'Ready'
        }

        It 'skips users whose sign-in name and primary email address would not match after the move' {
            $Response = Invoke-ExecEmailDomainMigration -Request (New-MigrationRequest @{ Preview = $true; SkipCollisions = $false })
            $Frank = Get-Row $Response 'frank'
            $Frank.status | Should -Be 'Skipped'
            $Frank.reason | Should -BeLike 'The sign-in name (frank@new.com) and primary email address (f.smith@new.com) would not match after the move*'
            (Get-Row $Response 'dave').reason | Should -BeLike 'The sign-in name (dave@other.com) and primary email address (dave@new.com) would not match*'
            (Get-Row $Response 'alice').status | Should -Be 'Ready'
            (Get-Row $Response 'nomail').status | Should -Be 'Ready'
        }

        It 'flags users whose sign-in name and primary email address differ' {
            $Response = Invoke-ExecEmailDomainMigration -Request (New-MigrationRequest @{ Preview = $true })
            (Get-Row $Response 'frank').mismatch | Should -BeTrue
            (Get-Row $Response 'dave').mismatch | Should -BeTrue
            (Get-Row $Response 'alice').mismatch | Should -BeFalse
            (Get-Row $Response 'nomail').mismatch | Should -BeFalse
        }

        It 'returns 400 for an unknown action' {
            $Response = Invoke-ExecEmailDomainMigration -Request (New-MigrationRequest @{ Users = @('frank'); Action = 'Delete' })
            $Response.StatusCode | Should -Be ([System.Net.HttpStatusCode]::BadRequest)
            Should -Invoke New-GraphGetRequest -Times 0
        }

        It 'never changes the sign-in name without the primary email address' {
            $null = Invoke-ExecEmailDomainMigration -Request (New-MigrationRequest @{ Users = @('frank', 'alice') })
            Should -Invoke New-GraphBulkRequest -Times 1 -Exactly -ParameterFilter { @($Requests.id) -join ',' -eq 'alice' }
            (@($script:ExoSent.OperationGuid) -join ',') | Should -Be 'alice'
        }
    }

    Context 'apply' {
        It 'changes the UPN through Graph and the addresses through Exchange, keeping the old address as an alias' {
            $Response = Invoke-ExecEmailDomainMigration -Request (New-MigrationRequest @{ Users = @('alice') })
            $Response.StatusCode | Should -Be ([System.Net.HttpStatusCode]::OK)
            @($Response.Body.Results)[0].state | Should -Be 'success'
            @($Response.Body.Results)[0].resultText | Should -BeLike '*alice@old.com kept as an alias*'
            Should -Invoke New-GraphBulkRequest -Times 1 -Exactly -ParameterFilter {
                $Requests.Count -eq 1 -and $Requests[0].url -eq 'users/alice' -and $Requests[0].body.userPrincipalName -eq 'alice@new.com'
            }
            Should -Invoke New-ExoBulkRequest -Times 1 -Exactly -ParameterFilter {
                $Parameters = $cmdletArray[0].CmdletInput.Parameters
                $Parameters.Identity -eq 'g-alice' -and ($Parameters.EmailAddresses -join ',') -ceq 'SMTP:alice@new.com,smtp:alice@old.com,smtp:alice@old.onmicrosoft.com'
            }
        }

        It 'always keeps the old primary address of a group as an alias' {
            $null = Invoke-ExecEmailDomainMigration -Request (New-MigrationRequest @{ IncludeGroups = $true; Users = @('m365') })
            ($script:ExoSent[0].CmdletInput.Parameters.EmailAddresses -join ',') | Should -BeExactly 'SMTP:team@new.com,SPO:SPO_1@SPO_2,smtp:team@old.com,smtp:team@old.onmicrosoft.com'
        }

        It 'reports every user as failed when the Graph batch throws, and still moves groups' {
            Mock New-GraphBulkRequest { throw 'Graph is down' }
            $Response = Invoke-ExecEmailDomainMigration -Request (New-MigrationRequest @{ IncludeGroups = $true; Users = @('alice', 'nomail', 'm365') })
            $Response.StatusCode | Should -Be ([System.Net.HttpStatusCode]::MultiStatus)
            $Texts = @($Response.Body.Results).Where({ $_.state -eq 'error' }).resultText | Sort-Object
            $Texts | Should -Be @('Alice: Could not change the sign-in name: Graph is down', 'No Mail: Could not change the sign-in name: Graph is down')
            @($Response.Body.Results).Where({ $_.state -eq 'success' }).resultText | Should -BeLike 'Team: primary email address is now team@new.com*'
            (@($script:ExoSent.OperationGuid) -join ',') | Should -Be 'm365'
        }

        It 'returns 500 when the Graph batch throws for every selected user' {
            Mock New-GraphBulkRequest { throw 'Graph is down' }
            $Response = Invoke-ExecEmailDomainMigration -Request (New-MigrationRequest @{ Users = @('alice', 'nomail') })
            $Response.StatusCode | Should -Be ([System.Net.HttpStatusCode]::InternalServerError)
            @($Response.Body.Results.state) | Should -Be @('error', 'error')
            Should -Invoke New-ExoBulkRequest -Times 0
        }

        It 'reports the sign-in name change and the email address error when Exchange throws after Graph succeeded' {
            Mock New-ExoBulkRequest { throw 'Exchange is down' }
            $Response = Invoke-ExecEmailDomainMigration -Request (New-MigrationRequest @{ Users = @('alice', 'nomail') })
            $Response.StatusCode | Should -Be ([System.Net.HttpStatusCode]::MultiStatus)
            @($Response.Body.Results).Where({ $_.state -eq 'error' }).resultText | Should -Be 'Alice: sign-in name is now alice@new.com, but could not change the email address: Exchange is down'
            @($Response.Body.Results).Where({ $_.state -eq 'success' }).resultText | Should -Be 'No Mail: sign-in name is now nomail@new.com.'
        }

        It 'reports skipped and privileged users without counting them as failures' {
            Mock Assert-CippPrivilegedUserAccess { @('nomail') }
            $Response = Invoke-ExecEmailDomainMigration -Request (New-MigrationRequest @{ Users = @('alice', 'bob', 'nomail', 'gone') })
            $Response.StatusCode | Should -Be ([System.Net.HttpStatusCode]::OK)
            $States = @{}
            foreach ($Result in $Response.Body.Results) { $States[$Result.resultText.Split(':')[0]] = $Result.state }
            $States['Alice'] | Should -Be 'success'
            $States['Bob'] | Should -Be 'warning'
            $States['No Mail'] | Should -Be 'warning'
            $States['gone'] | Should -Be 'warning'
            Should -Invoke New-GraphBulkRequest -Times 1 -Exactly -ParameterFilter { (@($Requests.id) -join ',') -eq 'alice' }
        }

        It 'returns 207 when one user fails, and does not change the mailbox of a user whose UPN failed' {
            $script:FailUpn = @('alice')
            $Response = Invoke-ExecEmailDomainMigration -Request (New-MigrationRequest @{ Users = @('alice', 'nomail') })
            $Response.StatusCode | Should -Be ([System.Net.HttpStatusCode]::MultiStatus)
            @($Response.Body.Results).Where({ $_.state -eq 'error' }).resultText | Should -Be 'Alice: Could not change the sign-in name: UPN rejected'
            Should -Invoke New-ExoBulkRequest -Times 0
        }

        It 'returns 500 when every user fails' {
            $script:FailMailbox = @('alice')
            $script:FailUpn = @('nomail')
            $Response = Invoke-ExecEmailDomainMigration -Request (New-MigrationRequest @{ Users = @('alice', 'nomail') })
            $Response.StatusCode | Should -Be ([System.Net.HttpStatusCode]::InternalServerError)
            @($Response.Body.Results).Where({ $_.state -eq 'error' }).Count | Should -Be 2
        }

        It 'treats a mailbox change Exchange never answered as failed' {
            Mock New-ExoBulkRequest { }
            $Response = Invoke-ExecEmailDomainMigration -Request (New-MigrationRequest @{ Users = @('alice') })
            $Response.StatusCode | Should -Be ([System.Net.HttpStatusCode]::InternalServerError)
            @($Response.Body.Results)[0].resultText | Should -BeLike '*Exchange did not answer*'
        }
    }

    Context 'groups' {
        It 'leaves groups out unless asked' {
            $Response = Invoke-ExecEmailDomainMigration -Request (New-MigrationRequest @{ Preview = $true })
            foreach ($Id in 'm365', 'dl', 'g-ddg', 'sec', 'help') { @($Response.Body.Results.id) | Should -Not -Contain $Id }
        }

        It 'plans the primary address of Microsoft 365 groups, distribution lists and dynamic distribution lists, never a UPN' {
            $Response = Invoke-ExecEmailDomainMigration -Request (New-MigrationRequest @{ Preview = $true; IncludeGroups = $true })
            foreach ($Case in @(@('m365', 'team@new.com'), @('dl', 'salesdl@new.com'), @('g-ddg', 'everyone@new.com'))) {
                $Row = Get-Row $Response $Case[0]
                $Row.type | Should -Be 'Group'
                $Row.status | Should -Be 'Ready'
                $Row.newPrimarySmtpAddress | Should -Be $Case[1]
                $Row.newUserPrincipalName | Should -BeNullOrEmpty
            }
            (Get-Row $Response 'g-ddg').exchangeIdentity | Should -Be 'g-ddg'
        }

        It 'skips synced groups and groups whose new address is taken' {
            $Response = Invoke-ExecEmailDomainMigration -Request (New-MigrationRequest @{ Preview = $true; IncludeGroups = $true })
            (Get-Row $Response 'sec').reason | Should -BeLike 'Synced from on-premises*'
            (Get-Row $Response 'help').reason | Should -Be 'help@new.com is already used by another user, group or contact.'
        }

        It 'changes each group with its own cmdlet in one Exchange batch, and never checks groups for privileged roles' {
            $Response = Invoke-ExecEmailDomainMigration -Request (New-MigrationRequest @{ IncludeGroups = $true; Users = @('alice', 'm365', 'dl', 'g-ddg') })
            $Response.StatusCode | Should -Be ([System.Net.HttpStatusCode]::OK)
            @($Response.Body.Results.state) | Should -Be @('success', 'success', 'success', 'success')
            Should -Invoke New-ExoBulkRequest -Times 1 -Exactly
            Should -Invoke Assert-CippPrivilegedUserAccess -Times 1 -Exactly -ParameterFilter { (@($UserId) -join ',') -eq 'alice' }
            Should -Invoke New-GraphBulkRequest -Times 1 -Exactly -ParameterFilter { (@($Requests.id) -join ',') -eq 'alice' }
            $Sent = @{}
            foreach ($Cmd in $script:ExoSent) { $Sent[$Cmd.OperationGuid] = $Cmd.CmdletInput }
            $Sent['alice'].CmdletName | Should -Be 'Set-Mailbox'
            $Sent['m365'].CmdletName | Should -Be 'Set-UnifiedGroup'
            $Sent['m365'].Parameters.Identity | Should -Be 'g-m365'
            ($Sent['m365'].Parameters.EmailAddresses -join ',') | Should -BeExactly 'SMTP:team@new.com,SPO:SPO_1@SPO_2,smtp:team@old.com,smtp:team@old.onmicrosoft.com'
            $Sent['dl'].CmdletName | Should -Be 'Set-DistributionGroup'
            ($Sent['dl'].Parameters.EmailAddresses -join ',') | Should -BeExactly 'SMTP:salesdl@new.com,smtp:salesdl@old.com,X500:/o=x/cn=salesdl'
            $Sent['g-ddg'].CmdletName | Should -Be 'Set-DynamicDistributionGroup'
            $Sent['g-ddg'].Parameters.Identity | Should -Be 'g-ddg'
            ($Sent['g-ddg'].Parameters.EmailAddresses -join ',') | Should -BeExactly 'SMTP:everyone@new.com,smtp:everyone@old.com'
        }

    }

    Context 'fixing sign-in name and email address mismatches' {
        It 'makes the sign-in name the primary email address, keeping the old primary as an alias' {
            $Response = Invoke-ExecEmailDomainMigration -Request (New-MigrationRequest @{ Action = 'UseSignInNameAsEmail'; Users = @('frank') })
            $Response.StatusCode | Should -Be ([System.Net.HttpStatusCode]::OK)
            @($Response.Body.Results)[0].resultText | Should -Be 'Frank: primary email address is now frank@old.com (f.smith@old.com kept as an alias).'
            Should -Invoke New-GraphBulkRequest -Times 0
            $script:ExoSent.Count | Should -Be 1
            $script:ExoSent[0].CmdletInput.CmdletName | Should -Be 'Set-Mailbox'
            $script:ExoSent[0].CmdletInput.Parameters.Identity | Should -Be 'g-frank'
            ($script:ExoSent[0].CmdletInput.Parameters.EmailAddresses -join ',') | Should -BeExactly 'SMTP:frank@old.com,smtp:f.smith@old.com,smtp:frank@old.onmicrosoft.com'
        }

        It 'makes the primary email address the sign-in name' {
            $Response = Invoke-ExecEmailDomainMigration -Request (New-MigrationRequest @{ Action = 'UseEmailAsSignInName'; Users = @('frank', 'dave') })
            $Response.StatusCode | Should -Be ([System.Net.HttpStatusCode]::OK)
            @($Response.Body.Results.state) | Should -Be @('success', 'success')
            Should -Invoke New-GraphBulkRequest -Times 1 -Exactly -ParameterFilter {
                $Sent = @{}
                foreach ($R in $Requests) { $Sent[$R.url] = $R.body.userPrincipalName }
                $Requests.Count -eq 2 -and $Requests[0].method -eq 'PATCH' -and $Sent['users/frank'] -eq 'f.smith@old.com' -and $Sent['users/dave'] -eq 'dave@old.com'
            }
            Should -Invoke New-ExoBulkRequest -Times 0
        }

        It 'skips a primary email address on a domain that is not verified' {
            $Response = Invoke-ExecEmailDomainMigration -Request (New-MigrationRequest @{ Action = 'UseEmailAsSignInName'; Users = @('gina') })
            @($Response.Body.Results)[0].state | Should -Be 'warning'
            @($Response.Body.Results)[0].resultText | Should -Be 'Gina: skipped. gina@pending.com is not on a verified domain of this tenant, so it cannot be a sign-in name.'
            Should -Invoke New-GraphBulkRequest -Times 0
        }

        It '<Action> only changes users whose sign-in name and primary email address differ' -TestCases @(
            @{ Action = 'UseSignInNameAsEmail' }
            @{ Action = 'UseEmailAsSignInName' }
        ) {
            $Response = Invoke-ExecEmailDomainMigration -Request (New-MigrationRequest @{ Action = $Action; IncludeGroups = $true; Users = @('alice', 'nomail', 'm365', 'frank') })
            $Response.StatusCode | Should -Be ([System.Net.HttpStatusCode]::OK)
            foreach ($Name in 'Alice', 'No Mail', 'Team') {
                @($Response.Body.Results).Where({ $_.resultText -like "$Name`:*" })[0].resultText | Should -Be "$Name`: skipped. Its sign-in name and primary email address already match."
            }
            if ($Action -eq 'UseSignInNameAsEmail') {
                (@($script:ExoSent.OperationGuid) -join ',') | Should -Be 'frank'
                Should -Invoke New-GraphBulkRequest -Times 0
            } else {
                Should -Invoke New-GraphBulkRequest -Times 1 -Exactly -ParameterFilter { (@($Requests.id) -join ',') -eq 'frank' }
                Should -Invoke New-ExoBulkRequest -Times 0
            }
        }

        It 'skips a fix whose address is already used by someone else' {
            Mock New-ExoRequest { @($script:Recipients) + [pscustomobject]@{ ExternalDirectoryObjectId = 'other'; Guid = 'g-other'; DisplayName = 'Other'; WindowsLiveID = 'other@old.com'; PrimarySmtpAddress = 'other@old.com'; EmailAddresses = @('SMTP:other@old.com', 'smtp:frank@old.com'); RecipientTypeDetails = 'UserMailbox'; IsDirSynced = $false } }
            $Response = Invoke-ExecEmailDomainMigration -Request (New-MigrationRequest @{ Action = 'UseSignInNameAsEmail'; Users = @('frank') })
            @($Response.Body.Results)[0].resultText | Should -Be 'Frank: skipped. frank@old.com is already used by another user, group or contact.'
        }
    }

    Context 'adding the new domain as an alias' {
        It 'plans an alias from the primary email address and never a new sign-in name or primary address' {
            $Response = Invoke-ExecEmailDomainMigration -Request (New-MigrationRequest @{ Action = 'AddAlias'; Preview = $true })
            $Response.StatusCode | Should -Be ([System.Net.HttpStatusCode]::OK)
            foreach ($Row in $Response.Body.Results) {
                $Row.newUserPrincipalName | Should -BeNullOrEmpty
                $Row.newPrimarySmtpAddress | Should -BeNullOrEmpty
            }
            $Alice = Get-Row $Response 'alice'
            $Alice.status | Should -Be 'Ready'
            $Alice.newAlias | Should -Be 'alice@new.com'
            $Frank = Get-Row $Response 'frank'
            $Frank.status | Should -Be 'Ready'
            $Frank.newAlias | Should -Be 'f.smith@new.com'
            (Get-Row $Response 'dave').newAlias | Should -Be 'dave@new.com'
            foreach ($Id in 'nomail', 'gina', 'shared', 'm365') { @($Response.Body.Results.id) | Should -Not -Contain $Id }
        }

        It 'skips synced objects, collisions and % addresses with the reason' {
            $Response = Invoke-ExecEmailDomainMigration -Request (New-MigrationRequest @{ Action = 'AddAlias'; Preview = $true; IncludeGroups = $true })
            (Get-Row $Response 'bob').reason | Should -BeLike 'Synced from on-premises*'
            (Get-Row $Response 'sec').reason | Should -BeLike 'Synced from on-premises*'
            (Get-Row $Response 'carol').reason | Should -Be 'carol@new.com is already used by another user, group or contact.'
            (Get-Row $Response 'dave').reason | Should -Be 'dave@new.com is already used by another user, group or contact.'
            (Get-Row $Response 'help').reason | Should -Be 'help@new.com is already used by another user, group or contact.'
            (Get-Row $Response 'erin').reason | Should -BeLike '*% sign*'
            (Get-Row (Invoke-ExecEmailDomainMigration -Request (New-MigrationRequest @{ Action = 'AddAlias'; Preview = $true; SkipCollisions = $false })) 'carol').status | Should -Be 'Ready'
        }

        It 'skips an object that already has the address, in any case' {
            Mock New-ExoRequest { @($script:Recipients) + [pscustomobject]@{ ExternalDirectoryObjectId = 'hank'; Guid = 'g-hank'; DisplayName = 'Hank'; WindowsLiveID = 'hank@old.com'; PrimarySmtpAddress = 'hank@old.com'; EmailAddresses = @('SMTP:hank@old.com', 'smtp:HANK@New.com'); RecipientTypeDetails = 'UserMailbox'; IsDirSynced = $false } }
            $Response = Invoke-ExecEmailDomainMigration -Request (New-MigrationRequest @{ Action = 'AddAlias'; Users = @('hank') })
            $Response.StatusCode | Should -Be ([System.Net.HttpStatusCode]::OK)
            @($Response.Body.Results)[0].state | Should -Be 'warning'
            @($Response.Body.Results)[0].resultText | Should -Be 'Hank: skipped. It already has hank@new.com.'
            Should -Invoke New-ExoBulkRequest -Times 0
        }

        It 'adds the alias to mailboxes, shared mailboxes and groups with their own cmdlet, never touching the sign-in name' {
            $Response = Invoke-ExecEmailDomainMigration -Request (New-MigrationRequest @{ Action = 'AddAlias'; IncludeSharedMailboxes = $true; IncludeGroups = $true; Users = @('frank', 'shared', 'm365', 'dl', 'g-ddg') })
            $Response.StatusCode | Should -Be ([System.Net.HttpStatusCode]::OK)
            @($Response.Body.Results.resultText) | Should -Contain 'Sales Shared: added shared@new.com as an alias.'
            @($Response.Body.Results.resultText) | Should -Contain 'Frank: added f.smith@new.com as an alias.'
            @($Response.Body.Results.state) | Should -Be @('success', 'success', 'success', 'success', 'success')
            Should -Invoke New-GraphBulkRequest -Times 0
            Should -Invoke New-ExoBulkRequest -Times 1 -Exactly
            $Sent = @{}
            foreach ($Cmd in $script:ExoSent) { $Sent[$Cmd.OperationGuid] = $Cmd.CmdletInput }
            $Sent['frank'].CmdletName | Should -Be 'Set-Mailbox'
            ($Sent['frank'].Parameters.EmailAddresses -join ',') | Should -BeExactly 'SMTP:f.smith@old.com,smtp:Frank@old.com,smtp:frank@old.onmicrosoft.com,smtp:f.smith@new.com'
            $Sent['shared'].CmdletName | Should -Be 'Set-Mailbox'
            $Sent['shared'].Parameters.Identity | Should -Be 'g-shared'
            ($Sent['shared'].Parameters.EmailAddresses -join ',') | Should -BeExactly 'SMTP:shared@old.com,smtp:shared@new.com'
            $Sent['m365'].CmdletName | Should -Be 'Set-UnifiedGroup'
            ($Sent['m365'].Parameters.EmailAddresses -join ',') | Should -BeExactly 'SPO:SPO_1@SPO_2,SMTP:team@old.com,smtp:team@old.onmicrosoft.com,smtp:team@new.com'
            $Sent['dl'].CmdletName | Should -Be 'Set-DistributionGroup'
            ($Sent['dl'].Parameters.EmailAddresses -join ',') | Should -BeExactly 'SMTP:salesdl@old.com,X500:/o=x/cn=salesdl,smtp:salesdl@new.com'
            $Sent['g-ddg'].CmdletName | Should -Be 'Set-DynamicDistributionGroup'
            ($Sent['g-ddg'].Parameters.EmailAddresses -join ',') | Should -BeExactly 'SMTP:everyone@old.com,smtp:everyone@new.com'
        }

        It 'reports an Exchange failure per object' {
            $script:FailMailbox = @('alice')
            $Response = Invoke-ExecEmailDomainMigration -Request (New-MigrationRequest @{ Action = 'AddAlias'; Users = @('alice', 'frank') })
            $Response.StatusCode | Should -Be ([System.Net.HttpStatusCode]::MultiStatus)
            @($Response.Body.Results).Where({ $_.state -eq 'error' }).resultText | Should -Be 'Alice: Could not change the email address: Proxy address rejected'
        }

        It 'leaves newAlias empty for the other actions' {
            $Response = Invoke-ExecEmailDomainMigration -Request (New-MigrationRequest @{ Preview = $true })
            foreach ($Row in $Response.Body.Results) { $Row.newAlias | Should -BeNullOrEmpty }
        }
    }

    Context 'source of authority' {
        It 'moves objects Entra no longer syncs, even while Exchange still marks them as synced' {
            Mock New-ExoRequest { Get-RecipientsWith 'alice', 'dl' @{ IsDirSynced = $true } }
            $Response = Invoke-ExecEmailDomainMigration -Request (New-MigrationRequest @{ Preview = $true; IncludeGroups = $true })
            (Get-Row $Response 'alice').status | Should -Be 'Ready'
            (Get-Row $Response 'dl').status | Should -Be 'Ready'
            (Get-Row $Response 'bob').reason | Should -BeLike '*or move its source of authority to the cloud.'
            (Get-Row $Response 'sec').status | Should -Be 'Skipped'
        }

        It 'adds an alias to a synced mailbox whose Exchange attributes are managed in the cloud, but never moves it' {
            Mock New-ExoRequest { Get-RecipientsWith 'bob' @{ IsExchangeCloudManaged = $true } }
            $Alias = Invoke-ExecEmailDomainMigration -Request (New-MigrationRequest @{ Action = 'AddAlias'; Preview = $true; IncludeGroups = $true })
            (Get-Row $Alias 'bob').status | Should -Be 'Ready'
            (Get-Row $Alias 'bob').newAlias | Should -Be 'bob@new.com'
            (Get-Row $Alias 'sec').reason | Should -Be 'Synced from on-premises Active Directory. Add the address there, or manage its Exchange attributes in the cloud.'
            $Move = Invoke-ExecEmailDomainMigration -Request (New-MigrationRequest @{ Preview = $true })
            (Get-Row $Move 'bob').status | Should -Be 'Skipped'
        }

        It 'only looks up synced groups when groups are included' {
            $null = Invoke-ExecEmailDomainMigration -Request (New-MigrationRequest @{ Preview = $true })
            Should -Invoke New-GraphGetRequest -Times 0 -ParameterFilter { $uri -like '*/groups?*' }
        }
    }

    Context 'permission' {
        It 'is gated on its own Tenant.DomainMigration.ReadWrite permission' {
            (Get-Help Invoke-ExecEmailDomainMigration).Role | Should -Be 'Tenant.DomainMigration.ReadWrite'
        }
    }
}
