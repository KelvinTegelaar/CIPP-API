# Pester tests for Invoke-CIPPStandardDisableSharedMailbox
#
# Pins the behaviour behind the "denied deviation that never remediates" reports:
#   - a remediating run reports what it leaves behind, not the list it found. It used to disable
#     the accounts and then write the pre-remediation list to the compare field, so drift showed
#     the same deviation after every successful run;
#   - the selection itself covers both mailbox types and only accounts that are still enabled and
#     cloud-only. -and and -or share one precedence level in PowerShell and associate left to
#     right, so the unparenthesised original meant the same thing - these pin it against a
#     "fix" that regroups it as A -or (B -and C);
#   - the user cache and the Exchange mailbox list fail with distinct messages.

BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
    $Modules = Join-Path $RepoRoot 'Modules'
    # Resolve by name under Modules/ so the test survives the function moving between modules.
    $StandardPath = Get-ChildItem -Path $Modules -Recurse -Filter 'Invoke-CIPPStandardDisableSharedMailbox.ps1' -File -ErrorAction SilentlyContinue |
        Select-Object -First 1 -ExpandProperty FullName
    if (-not $StandardPath) { throw 'Could not locate Invoke-CIPPStandardDisableSharedMailbox.ps1 under Modules/' }

    # Stubs mirror the real signatures and are advanced functions on purpose: strict parameter
    # binding makes signature drift in the standard fail loudly here instead of silently
    # landing in $args.
    function New-CIPPDbRequest { [CmdletBinding()] param($TenantFilter, $Type, $Fields) }
    function New-GraphGetRequest { [CmdletBinding()] param($uri, $tenantid, $scope, $AsApp, $noPagination, $NoAuthCheck, $skipTokenCache, $ComplexFilter, $CountOnly) }
    function New-GraphBulkRequest { [CmdletBinding()] param($tenantid, $NoAuthCheck, $scope, $asapp, $Requests, $NoPaginateIds, $Version, $Headers) }
    function Set-CIPPDBCacheUsers { [CmdletBinding()] param($TenantFilter) }
    function Write-LogMessage { [CmdletBinding()] param($API, $tenant, $Tenant2, $message, $sev, $headers, $LogData) }
    function Write-StandardsAlert { [CmdletBinding()] param($message, $object, $tenant, $standardName, $standardId) }
    function Set-CIPPStandardsCompareField { [CmdletBinding()] param($FieldName, $FieldValue, $CurrentValue, $ExpectedValue, $TenantFilter, $Tenant) }
    function Add-CIPPBPAField { [CmdletBinding()] param($FieldName, $FieldValue, $StoreAs, $Tenant) }
    function Get-NormalizedError { [CmdletBinding()] param($Message) $Message }
    function Get-CippException { [CmdletBinding()] param($Exception) @{ NormalizedError = $Exception.Exception.Message } }

    . $StandardPath

    # Script scope: Pester 5 evaluates the Describe body at discovery, so plain variables
    # declared there are not in scope inside It blocks or mocks at run time.
    $script:Tenant = 'contoso.onmicrosoft.com'

    # Both shapes go through ConvertFrom-Json, matching what the cache and the adminapi hand back.
    function script:New-CachedUser {
        param(
            [string]$Id,
            [string]$Upn,
            [bool]$Enabled = $true,
            [bool]$OnPremSynced = $false
        )
        [ordered]@{
            id                   = $Id
            userPrincipalName    = $Upn
            accountEnabled       = $Enabled
            onPremisesSyncEnabled = $OnPremSynced
        } | ConvertTo-Json -Depth 5 | ConvertFrom-Json
    }

    function script:New-Mailbox {
        param(
            [string]$Id,
            [string]$Upn,
            [string]$Type = 'SharedMailbox'
        )
        [ordered]@{
            ObjectKey            = $Id
            UserPrincipalName    = $Upn
            DisplayName          = $Upn
            RecipientTypeDetails = $Type
        } | ConvertTo-Json -Depth 5 | ConvertFrom-Json
    }
}

Describe 'Invoke-CIPPStandardDisableSharedMailbox' {
    BeforeEach {
        $script:logs = [System.Collections.Generic.List[object]]::new()
        $script:alerts = [System.Collections.Generic.List[object]]::new()
        $script:compare = [System.Collections.Generic.List[object]]::new()
        $script:patched = [System.Collections.Generic.List[string]]::new()
        $script:users = @()
        $script:mailboxes = @()
        # Object keys the bulk PATCH should answer with a failure instead of a 204.
        $script:failKeys = @()

        Mock -CommandName Add-CIPPBPAField -MockWith { }
        Mock -CommandName Set-CIPPDBCacheUsers -MockWith { }
        Mock -CommandName Write-LogMessage -MockWith {
            param($API, $tenant, $message, $sev, $LogData)
            $script:logs.Add(@{ Message = $message; Sev = $sev })
        }
        Mock -CommandName Write-StandardsAlert -MockWith {
            param($message, $object, $tenant, $standardName, $standardId)
            $script:alerts.Add(@{ Message = $message; Object = @($object) })
        }
        Mock -CommandName Set-CIPPStandardsCompareField -MockWith {
            param($FieldName, $FieldValue, $CurrentValue, $ExpectedValue, $TenantFilter, $Tenant)
            $script:compare.Add(@{ Current = $CurrentValue; Expected = $ExpectedValue })
        }
        Mock -CommandName New-CIPPDbRequest -MockWith { $script:users }
        Mock -CommandName New-GraphGetRequest -MockWith { $script:mailboxes }
        Mock -CommandName New-GraphBulkRequest -MockWith {
            param($tenantid, $Requests)
            @(foreach ($Request in $Requests) {
                    $Key = $Request.url -replace '^users/', ''
                    $script:patched.Add($Key)
                    if ($script:failKeys -contains $Key) {
                        [pscustomobject]@{ id = $Request.id; status = 403; body = [pscustomobject]@{ error = [pscustomobject]@{ message = 'Insufficient privileges' } } }
                    } else {
                        [pscustomobject]@{ id = $Request.id; status = 204; body = $null }
                    }
                })
        }
    }

    Context 'selection' {
        It 'reports a shared mailbox whose Entra account is already disabled as compliant' {
            $script:users = @(New-CachedUser -Id 'shared1' -Upn 'shared@contoso.com' -Enabled $false)
            $script:mailboxes = @(New-Mailbox -Id 'shared1' -Upn 'shared@contoso.com')

            Invoke-CIPPStandardDisableSharedMailbox -Tenant $script:Tenant -Settings @{ report = $true }

            $script:compare.Count | Should -Be 1
            @($script:compare[0].Current.DisableSharedMailbox) | Should -BeNullOrEmpty
        }

        It 'reports a shared mailbox whose Entra account is still enabled as non-compliant' {
            $script:users = @(New-CachedUser -Id 'shared1' -Upn 'shared@contoso.com')
            $script:mailboxes = @(New-Mailbox -Id 'shared1' -Upn 'shared@contoso.com')

            Invoke-CIPPStandardDisableSharedMailbox -Tenant $script:Tenant -Settings @{ report = $true }

            @($script:compare[0].Current.DisableSharedMailbox).UserPrincipalName | Should -Be 'shared@contoso.com'
            @($script:compare[0].Expected.DisableSharedMailbox) | Should -BeNullOrEmpty
        }

        It 'applies the same join to scheduling mailboxes and skips directory-synced accounts' {
            $script:users = @(
                New-CachedUser -Id 'room1' -Upn 'room@contoso.com'
                New-CachedUser -Id 'sched1' -Upn 'sched@contoso.com' -Enabled $false
                New-CachedUser -Id 'synced1' -Upn 'synced@contoso.com' -OnPremSynced $true
            )
            $script:mailboxes = @(
                New-Mailbox -Id 'room1' -Upn 'room@contoso.com' -Type 'SchedulingMailbox'
                New-Mailbox -Id 'sched1' -Upn 'sched@contoso.com' -Type 'SchedulingMailbox'
                New-Mailbox -Id 'synced1' -Upn 'synced@contoso.com'
                New-Mailbox -Id 'user1' -Upn 'user@contoso.com' -Type 'UserMailbox'
            )

            Invoke-CIPPStandardDisableSharedMailbox -Tenant $script:Tenant -Settings @{ report = $true }

            @($script:compare[0].Current.DisableSharedMailbox).UserPrincipalName | Should -Be 'room@contoso.com'
        }
    }

    Context 'remediation' {
        It 'disables only the mailboxes whose account is still enabled' {
            $script:users = @(
                New-CachedUser -Id 'enabled1' -Upn 'enabled@contoso.com'
                New-CachedUser -Id 'disabled1' -Upn 'disabled@contoso.com' -Enabled $false
            )
            $script:mailboxes = @(
                New-Mailbox -Id 'enabled1' -Upn 'enabled@contoso.com'
                New-Mailbox -Id 'disabled1' -Upn 'disabled@contoso.com'
            )

            Invoke-CIPPStandardDisableSharedMailbox -Tenant $script:Tenant -Settings @{ remediate = $true }

            @($script:patched) | Should -Be @('enabled1')
        }

        It 'reports the post-remediation state, not the state it found' {
            $script:users = @(New-CachedUser -Id 'enabled1' -Upn 'enabled@contoso.com')
            $script:mailboxes = @(New-Mailbox -Id 'enabled1' -Upn 'enabled@contoso.com')

            Invoke-CIPPStandardDisableSharedMailbox -Tenant $script:Tenant -Settings @{ remediate = $true; alert = $true; report = $true }

            @($script:patched) | Should -Be @('enabled1')
            @($script:compare[0].Current.DisableSharedMailbox) | Should -BeNullOrEmpty
            $script:alerts.Count | Should -Be 0
        }

        It 'keeps a mailbox it failed to disable in the report' {
            $script:users = @(
                New-CachedUser -Id 'ok1' -Upn 'ok@contoso.com'
                New-CachedUser -Id 'bad1' -Upn 'bad@contoso.com'
            )
            $script:mailboxes = @(
                New-Mailbox -Id 'ok1' -Upn 'ok@contoso.com'
                New-Mailbox -Id 'bad1' -Upn 'bad@contoso.com'
            )
            $script:failKeys = @('bad1')

            Invoke-CIPPStandardDisableSharedMailbox -Tenant $script:Tenant -Settings @{ remediate = $true; report = $true }

            @($script:compare[0].Current.DisableSharedMailbox).UserPrincipalName | Should -Be 'bad@contoso.com'
        }
    }

    Context 'failure reporting' {
        It 'names the cached user list when the database read fails' {
            Mock -CommandName New-CIPPDbRequest -MockWith { throw 'table unavailable' }

            Invoke-CIPPStandardDisableSharedMailbox -Tenant $script:Tenant -Settings @{ report = $true }

            Should -Invoke New-GraphGetRequest -Times 0 -Exactly
            @($script:logs | Where-Object { $_.Message -like '*could not read the cached user list*' }).Count | Should -Be 1
            $script:compare.Count | Should -Be 0
        }

        It 'names Exchange when the mailbox list fails' {
            $script:users = @(New-CachedUser -Id 'shared1' -Upn 'shared@contoso.com')
            Mock -CommandName New-GraphGetRequest -MockWith { throw 'Exchange is down' }

            Invoke-CIPPStandardDisableSharedMailbox -Tenant $script:Tenant -Settings @{ report = $true }

            @($script:logs | Where-Object { $_.Message -like '*could not list mailboxes from Exchange*' }).Count | Should -Be 1
            $script:compare.Count | Should -Be 0
        }

        It 'reports nothing at all when the user cache is empty' {
            $script:users = @()

            Invoke-CIPPStandardDisableSharedMailbox -Tenant $script:Tenant -Settings @{ report = $true }

            Should -Invoke New-GraphGetRequest -Times 0 -Exactly
            @($script:logs | Where-Object { $_.Message -like '*cached user list is empty*' }).Count | Should -Be 1
            $script:compare.Count | Should -Be 0
        }
    }
}
