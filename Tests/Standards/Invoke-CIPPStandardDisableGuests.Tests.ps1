# Pester tests for Invoke-CIPPStandardDisableGuests
#
# Pins the selection rules behind the "guest disabled despite recent activity" reports:
#   - inactivity is judged on the newest sign-in ATTEMPT, interactive or non-interactive - the
#     view the Entra portal and the inactive-guest alert give - not on the last successful
#     sign-in alone, which stays old while a blocked or disabled guest keeps trying;
#   - guests with no sign-in on record are skipped unless IncludeNeverSignedIn is on, and a
#     template that predates the switch behaves as off;
#   - a guest an admin re-enabled in the last 7 days is left alone.

BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
    $Modules = Join-Path $RepoRoot 'Modules'
    # Resolve by name under Modules/ so the test survives the functions moving between modules.
    $StandardPath = Get-ChildItem -Path $Modules -Recurse -Filter 'Invoke-CIPPStandardDisableGuests.ps1' -File -ErrorAction SilentlyContinue |
        Select-Object -First 1 -ExpandProperty FullName
    if (-not $StandardPath) { throw 'Could not locate Invoke-CIPPStandardDisableGuests.ps1 under Modules/' }
    $HelperPath = Get-ChildItem -Path $Modules -Recurse -Filter 'Get-CIPPLastSignInDateTime.ps1' -File -ErrorAction SilentlyContinue |
        Select-Object -First 1 -ExpandProperty FullName
    if (-not $HelperPath) { throw 'Could not locate Get-CIPPLastSignInDateTime.ps1 under Modules/' }

    # Stubs mirror the real signatures and are advanced functions on purpose: strict parameter
    # binding makes signature drift in the standard fail loudly here instead of silently
    # landing in $args.
    function Test-CIPPStandardLicense { [CmdletBinding()] param($StandardName, $TenantFilter, $Preset, [switch]$SkipLog) }
    function New-GraphGetRequest { [CmdletBinding()] param($uri, $tenantid, $scope, $AsApp, $noPagination, $NoAuthCheck, $skipTokenCache, $ComplexFilter, $CountOnly) }
    function New-GraphBulkRequest { [CmdletBinding()] param($tenantid, $NoAuthCheck, $scope, $asapp, $Requests, $NoPaginateIds, $Version, $Headers) }
    function Write-LogMessage { [CmdletBinding()] param($API, $tenant, $Tenant2, $message, $sev, $headers, $LogData) }
    function Write-StandardsAlert { [CmdletBinding()] param($message, $object, $tenant, $standardName, $standardId) }
    function Set-CIPPStandardsCompareField { [CmdletBinding()] param($FieldName, $FieldValue, $CurrentValue, $ExpectedValue, $TenantFilter, $Tenant) }
    function Add-CIPPBPAField { [CmdletBinding()] param($FieldName, $FieldValue, $StoreAs, $Tenant) }
    function Get-NormalizedError { [CmdletBinding()] param($Message) $Message }
    function Get-CippException { [CmdletBinding()] param($Exception) @{ NormalizedError = $Exception.Exception.Message } }

    . $HelperPath
    . $StandardPath

    # Script scope: Pester 5 evaluates the Describe body at discovery, so plain variables
    # declared there are not in scope inside It blocks or mocks at run time.
    $script:Tenant = 'contoso.onmicrosoft.com'
    $script:Now = (Get-Date).ToUniversalTime()

    # Guests go through ConvertFrom-Json, the shape New-GraphGetRequest hands the standard. Each
    # *DaysAgo is how far back that signInActivity timestamp sits; leave all three out for a guest
    # with no sign-in on record.
    function script:New-Guest {
        param(
            [string]$Id,
            [string]$Upn,
            [string]$State = 'Accepted',
            [int]$CreatedDaysAgo = 400,
            [Nullable[int]]$InteractiveDaysAgo,
            [Nullable[int]]$NonInteractiveDaysAgo,
            [Nullable[int]]$SuccessfulDaysAgo
        )
        $Stamp = { param($DaysAgo) if ($null -ne $DaysAgo) { $script:Now.AddDays(-$DaysAgo).ToString('o') } else { $null } }
        $Guest = [ordered]@{
            id                = $Id
            userPrincipalName = $Upn
            mail              = $Upn
            userType          = 'Guest'
            accountEnabled    = $true
            createdDateTime   = $script:Now.AddDays(-$CreatedDaysAgo).ToString('o')
            externalUserState = $State
        }
        if ($null -ne $InteractiveDaysAgo -or $null -ne $NonInteractiveDaysAgo -or $null -ne $SuccessfulDaysAgo) {
            $Guest.signInActivity = [ordered]@{
                lastSignInDateTime               = & $Stamp $InteractiveDaysAgo
                lastNonInteractiveSignInDateTime = & $Stamp $NonInteractiveDaysAgo
                lastSuccessfulSignInDateTime     = & $Stamp $SuccessfulDaysAgo
            }
        }
        $Guest | ConvertTo-Json -Depth 5 | ConvertFrom-Json
    }
}

Describe 'Invoke-CIPPStandardDisableGuests' {
    BeforeEach {
        $script:logs = [System.Collections.Generic.List[object]]::new()
        $script:alerts = [System.Collections.Generic.List[object]]::new()
        $script:compare = [System.Collections.Generic.List[object]]::new()
        $script:disabled = [System.Collections.Generic.List[string]]::new()
        $script:guests = @()
        $script:audits = @()

        Mock -CommandName Test-CIPPStandardLicense -MockWith { $true }
        Mock -CommandName Add-CIPPBPAField -MockWith { }
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
        Mock -CommandName New-GraphGetRequest -MockWith {
            param($uri, $tenantid, $scope)
            if ($uri -like '*directoryAudits*') { return $script:audits }
            return $script:guests
        }
        Mock -CommandName New-GraphBulkRequest -MockWith {
            param($tenantid, $Requests)
            @(foreach ($Request in $Requests) {
                    $script:disabled.Add(($Request.url -replace '^users/', ''))
                    [pscustomobject]@{ id = $Request.id; status = 204; body = $null }
                })
        }
    }

    Context 'inactivity is judged on the newest sign-in attempt' {
        It 'keeps a guest whose last successful sign-in is old but who attempted a sign-in inside the window' {
            # The reported shape: a successful sign-in 300 days back, an interactive attempt 154 days
            # back and a non-interactive attempt 3 days back, against a 180-day threshold.
            $script:guests = @(New-Guest -Id 'g1' -Upn 'bas_example.com#EXT#@contoso.onmicrosoft.com' -SuccessfulDaysAgo 300 -InteractiveDaysAgo 154 -NonInteractiveDaysAgo 3)

            Invoke-CIPPStandardDisableGuests -Tenant $script:Tenant -Settings @{ remediate = $true; days = 180 }

            Should -Invoke New-GraphBulkRequest -Times 0 -Exactly
            @($script:disabled) | Should -BeNullOrEmpty
            @($script:logs | Where-Object { $_.Message -like '*already compliant*' }).Count | Should -Be 1
        }

        It 'disables a guest whose newest attempt of any kind is outside the window, and logs that date' {
            $script:guests = @(
                New-Guest -Id 'stale' -Upn 'stale@example.com' -SuccessfulDaysAgo 250 -InteractiveDaysAgo 200 -NonInteractiveDaysAgo 190
                New-Guest -Id 'active' -Upn 'active@example.com' -SuccessfulDaysAgo 250 -InteractiveDaysAgo 200 -NonInteractiveDaysAgo 100
            )

            Invoke-CIPPStandardDisableGuests -Tenant $script:Tenant -Settings @{ remediate = $true; days = 180 }

            @($script:disabled) | Should -Be @('stale')
            $Lines = @($script:logs | Where-Object { $_.Message -like 'Disabled guest stale@example.com (stale). Reason: last sign-in: *' })
            $Lines.Count | Should -Be 1
            # The newest attempt (non-interactive, 190 days back) is the one reported - not the successful one.
            $Logged = ([datetime]($Lines[0].Message -replace '^.*Reason: last sign-in: ', '')).ToUniversalTime()
            [math]::Abs(($Logged - $script:Now.AddDays(-190)).TotalMinutes) | Should -BeLessThan 1
        }

        It 'counts a lastSuccessfulSignInDateTime that runs ahead of both attempt timestamps as activity' {
            $script:guests = @(New-Guest -Id 'ahead' -Upn 'ahead@example.com' -InteractiveDaysAgo 200 -SuccessfulDaysAgo 10)

            Invoke-CIPPStandardDisableGuests -Tenant $script:Tenant -Settings @{ remediate = $true; days = 180 }

            @($script:disabled) | Should -BeNullOrEmpty
        }
    }

    Context 'guests with no sign-in on record' {
        It 'are skipped when the template predates the switch or has it off' {
            $script:guests = @(New-Guest -Id 'pending' -Upn 'pending@example.com' -State 'PendingAcceptance')

            Invoke-CIPPStandardDisableGuests -Tenant $script:Tenant -Settings @{ remediate = $true; days = 90 }
            Invoke-CIPPStandardDisableGuests -Tenant $script:Tenant -Settings @{ remediate = $true; days = 90; IncludeNeverSignedIn = $false }

            Should -Invoke New-GraphBulkRequest -Times 0 -Exactly
            @($script:disabled) | Should -BeNullOrEmpty
        }

        It 'are disabled only when IncludeNeverSignedIn is on, with the invitation age as the reason' {
            $script:guests = @(
                New-Guest -Id 'pending' -Upn 'pending@example.com' -State 'PendingAcceptance'
                New-Guest -Id 'fresh' -Upn 'fresh@example.com' -InteractiveDaysAgo 5
            )

            Invoke-CIPPStandardDisableGuests -Tenant $script:Tenant -Settings @{ remediate = $true; days = 90; IncludeNeverSignedIn = $true }

            @($script:disabled) | Should -Be @('pending')
            @($script:logs | Where-Object { $_.Message -like 'Disabled guest pending@example.com (pending). Reason: never signed in, created *' }).Count | Should -Be 1
        }
    }

    Context 'recently re-enabled guests' {
        It 'are left alone for 7 days after an admin re-enables them' {
            $script:guests = @(New-Guest -Id 'stale' -Upn 'stale@example.com' -InteractiveDaysAgo 200)
            $script:audits = @([pscustomobject]@{ targetResources = @([pscustomobject]@{ id = 'stale' }) })

            Invoke-CIPPStandardDisableGuests -Tenant $script:Tenant -Settings @{ remediate = $true; days = 90 }

            Should -Invoke New-GraphBulkRequest -Times 0 -Exactly
            @($script:disabled) | Should -BeNullOrEmpty
        }
    }

    Context 'alert and report' {
        It 'splits stale sign-ins from never-signed-in guests and records the switch' {
            $script:guests = @(
                New-Guest -Id 'stale' -Upn 'stale@example.com' -InteractiveDaysAgo 200
                New-Guest -Id 'pending' -Upn 'pending@example.com' -State 'PendingAcceptance'
                New-Guest -Id 'active' -Upn 'active@example.com' -NonInteractiveDaysAgo 2
            )

            Invoke-CIPPStandardDisableGuests -Tenant $script:Tenant -Settings @{ alert = $true; report = $true; days = 90; IncludeNeverSignedIn = $true }

            $script:alerts.Count | Should -Be 1
            $script:alerts[0].Message | Should -Match '2 total \(1 with no sign-in attempt in 90 days, 1 never signed in'
            @($script:alerts[0].Object | Where-Object { $_.NeverSignedIn }).id | Should -Be 'pending'

            $script:compare.Count | Should -Be 1
            $Current = $script:compare[0].Current
            $Current.GuestsDisabledAfterDays | Should -Be 90
            $Current.GuestsIncludeNeverSignedIn | Should -BeTrue
            $Current.GuestsDisabledAccountCount | Should -Be 2
            $Current.GuestsStaleSignInCount | Should -Be 1
            $Current.GuestsNeverSignedInCount | Should -Be 1
            @($Current.GuestsNeverSignedInDetails).id | Should -Be 'pending'
            @($Current.GuestsDisabledAccountDetails | Where-Object { -not $_.NeverSignedIn }).LastSignInDateTime | Should -Not -BeNullOrEmpty

            $Expected = $script:compare[0].Expected
            $Expected.GuestsDisabledAccountCount | Should -Be 0
            $Expected.GuestsStaleSignInCount | Should -Be 0
            $Expected.GuestsNeverSignedInCount | Should -Be 0
            $Expected.GuestsIncludeNeverSignedIn | Should -BeTrue
        }

        It 'reports the switch off and no never-signed-in guests when the template omits it' {
            $script:guests = @(New-Guest -Id 'pending' -Upn 'pending@example.com' -State 'PendingAcceptance')

            Invoke-CIPPStandardDisableGuests -Tenant $script:Tenant -Settings @{ report = $true; days = 90 }

            $Current = $script:compare[0].Current
            $Current.GuestsIncludeNeverSignedIn | Should -BeFalse
            $Current.GuestsDisabledAccountCount | Should -Be 0
            $Current.GuestsNeverSignedInCount | Should -Be 0
        }
    }
}
