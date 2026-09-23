BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
    $script:OriginalRoot = $env:CIPPRootPath
    $env:CIPPRootPath = $RepoRoot
    function New-GraphBulkRequest { param($Requests, $tenantid, $asapp) }
    function ConvertTo-CIPPODataFilterValue { param($Value, $Type) $Value }
    . (Join-Path $RepoRoot 'Modules/CIPPCore/Public/BEC/Get-CIPPBecHeuristics.ps1')
    . (Join-Path $RepoRoot 'Modules/CIPPCore/Public/BEC/New-CIPPBecCollectorResult.ps1')
    . (Join-Path $RepoRoot 'Modules/CIPPCore/Public/BEC/ConvertTo-CIPPBecHostAddress.ps1')
    . (Join-Path $RepoRoot 'Modules/CIPPCore/Public/BEC/Get-CIPPBecDirectoryAudits.ps1')
    $script:Heuristics = Get-CIPPBecHeuristics
    $script:UserId = 'c0ffee00-0000-4000-8000-000000000001'
    $script:Start = [datetime]::new(2026, 8, 20, 9, 30, 0, [System.DateTimeKind]::Utc)
    $script:AdminActor = [pscustomobject]@{ user = [pscustomobject]@{ id = 'admin-id'; userPrincipalName = 'admin@contoso.com'; ipAddress = '198.51.100.7' }; app = $null }
    $script:AppActor = [pscustomobject]@{ user = $null; app = [pscustomobject]@{ appId = 'app-1'; displayName = 'Sync Tool' } }

    function Get-AuditFixture {
        param([string]$Id, [string]$Activity, [string]$When = '2026-08-21T10:00:00Z', $InitiatedBy = $script:AdminActor, $Targets = @())
        [pscustomobject]@{
            id                  = $Id
            activityDateTime    = $When
            activityDisplayName = $Activity
            category            = 'UserManagement'
            result              = 'success'
            resultReason        = ''
            loggedByService     = 'Core Directory'
            initiatedBy         = $InitiatedBy
            targetResources     = @($Targets)
        }
    }

    # Fixture-driven stand-in for the Graph batch: each direction answers from its own fixture,
    # status and nextLink, so a test can degrade one half without touching the other.
    function Invoke-FakeBulk {
        param($Requests)
        foreach ($Request in $Requests) {
            switch ($Request.id) {
                'Target' { if (-not $script:TargetMissing) { [pscustomobject]@{ id = 'Target'; status = $script:TargetStatus; body = [pscustomobject]@{ value = @($script:TargetFixture); '@odata.nextLink' = $script:TargetNextLink; error = [pscustomobject]@{ message = 'Insufficient privileges' } } } } }
                'Actor' { [pscustomobject]@{ id = 'Actor'; status = $script:ActorStatus; body = [pscustomobject]@{ value = @($script:ActorFixture); '@odata.nextLink' = $null; error = [pscustomobject]@{ message = 'Actor lookup failed' } } } }
            }
        }
    }
}

AfterAll {
    $env:CIPPRootPath = $script:OriginalRoot
}

Describe 'Get-CIPPBecDirectoryAudits' {
    BeforeEach {
        Mock New-GraphBulkRequest { Invoke-FakeBulk -Requests $Requests }
        Mock ConvertTo-CIPPODataFilterValue { $Value }
        $script:TargetFixture = @()
        $script:ActorFixture = @()
        $script:TargetStatus = 200
        $script:ActorStatus = 200
        $script:TargetNextLink = $null
        $script:TargetMissing = $false
    }

    It 'batches one target and one actor query with the escaped user id, window start, page size and eventual consistency' {
        $null = Get-CIPPBecDirectoryAudits -TenantFilter 'contoso.com' -UserId $script:UserId -StartDate $script:Start -Heuristics $script:Heuristics
        Should -Invoke ConvertTo-CIPPODataFilterValue -Times 1 -ParameterFilter { $Value -eq $script:UserId -and $Type -eq 'Guid' }
        Should -Invoke New-GraphBulkRequest -Times 1 -ParameterFilter {
            $Target = $Requests | Where-Object { $_.id -eq 'Target' }
            $Actor = $Requests | Where-Object { $_.id -eq 'Actor' }
            @($Requests).Count -eq 2 -and
            $tenantid -eq 'contoso.com' -and $asapp -eq $true -and
            $Target.method -eq 'GET' -and $Actor.method -eq 'GET' -and
            $Target.url -like "auditLogs/directoryAudits?`$filter=activityDateTime ge 2026-08-20T09:30:00Z and targetResources/any(t:t/id eq '$($script:UserId)')&`$top=999&`$select=id,activityDateTime,*" -and
            $Actor.url -like "auditLogs/directoryAudits?`$filter=activityDateTime ge 2026-08-20T09:30:00Z and initiatedBy/user/id eq '$($script:UserId)'&`$top=999&`$select=id,activityDateTime,*" -and
            $Target.headers.ConsistencyLevel -eq 'eventual' -and $Actor.headers.ConsistencyLevel -eq 'eventual'
        }
    }

    It 'projects an audit record with its actor, IP, targets and truncated modified properties' {
        $Long = 'x' * 250
        $script:TargetFixture = @(
            Get-AuditFixture -Id 'a1' -Activity 'Update user' -When '2026-08-21T12:00:00+02:00' -Targets @(
                [pscustomobject]@{ id = $script:UserId; userPrincipalName = 'victim@contoso.com'; modifiedProperties = @(
                        [pscustomobject]@{ displayName = 'StrongAuthenticationMethod'; newValue = '[{"MethodType":6}]' }
                        [pscustomobject]@{ displayName = 'Included Updated Properties'; newValue = $Long }
                        [pscustomobject]@{ displayName = $null; newValue = 'ignored' }
                    ) }
                [pscustomobject]@{ id = 'g1'; displayName = 'Finance'; modifiedProperties = @() }
            )
        )
        $Result = Get-CIPPBecDirectoryAudits -TenantFilter 'contoso.com' -UserId $script:UserId -StartDate $script:Start -Heuristics $script:Heuristics
        $Result.Complete | Should -BeTrue
        $Result.Cap | Should -BeNullOrEmpty
        $Result.Error | Should -BeNullOrEmpty
        $Result.Count | Should -Be 1
        $Row = $Result.Data[0]
        $Row.Id | Should -Be 'a1'
        $Row.ActivityDateTime | Should -Be '2026-08-21T10:00:00Z' -Because 'timestamps are normalised to UTC'
        $Row.Activity | Should -Be 'Update user'
        $Row.Category | Should -Be 'UserManagement'
        $Row.Service | Should -Be 'Core Directory'
        $Row.Result | Should -Be 'success'
        $Row.InitiatedBy | Should -Be 'admin@contoso.com'
        $Row.InitiatedByType | Should -Be 'User'
        $Row.ClientIP | Should -Be '198.51.100.7'
        $Row.Targets | Should -Be 'victim@contoso.com, Finance'
        $Row.ModifiedProperties | Should -Match '^StrongAuthenticationMethod=\[\{"MethodType":6\}\]; Included Updated Properties=x{200}\.\.\.$' -Because 'unnamed properties are dropped and long values are cut at 200 characters'
        $Row.Direction | Should -Be 'Target'
        $Row.Flagged | Should -BeTrue -Because 'Update user is in the heuristics flag list'
    }

    It 'flags listed and security-info activities, sorts flagged newest-first, de-duplicates across directions and skips rows without an id' {
        $script:TargetFixture = @(
            Get-AuditFixture -Id 'a1' -Activity 'Add member to group' -When '2026-08-22T08:00:00Z'
            Get-AuditFixture -Id 'a2' -Activity 'User registered some security info' -When '2026-08-21T08:00:00Z'
            Get-AuditFixture -Id 'a3' -Activity 'Update Strong Authentication policy' -When '2026-08-22T09:00:00Z'
            Get-AuditFixture -Id 'a4' -Activity 'Register device' -When '2026-08-23T08:00:00Z'
            Get-AuditFixture -Id $null -Activity 'Update user' -When '2026-08-25T08:00:00Z'
        )
        $script:ActorFixture = @(
            Get-AuditFixture -Id 'a1' -Activity 'Add member to group' -When '2026-08-22T08:00:00Z'
            Get-AuditFixture -Id 'a5' -Activity 'Update group' -When '2026-08-24T08:00:00Z' -InitiatedBy $script:AppActor -Targets @([pscustomobject]@{ id = 'g2'; displayName = 'Sales' })
        )
        $Result = Get-CIPPBecDirectoryAudits -TenantFilter 'contoso.com' -UserId $script:UserId -StartDate $script:Start -Heuristics $script:Heuristics
        $Result.Complete | Should -BeTrue
        $Result.Data.Id | Should -Be @('a4', 'a3', 'a2', 'a5', 'a1') -Because 'flagged rows sort first, newest first within each group'
        ($Result.Data | Where-Object { $_.Id -eq 'a2' }).Flagged | Should -BeTrue -Because 'the security-info wildcard catches names outside the list'
        ($Result.Data | Where-Object { $_.Id -eq 'a3' }).Flagged | Should -BeTrue -Because 'the Strong Authentication wildcard catches names outside the list'
        ($Result.Data | Where-Object { $_.Id -eq 'a1' }).Flagged | Should -BeFalse
        ($Result.Data | Where-Object { $_.Id -eq 'a1' }).Direction | Should -Be 'Target' -Because 'the first direction to see an id wins'
        $App = $Result.Data | Where-Object { $_.Id -eq 'a5' }
        $App.Direction | Should -Be 'Actor'
        $App.InitiatedBy | Should -Be 'Sync Tool'
        $App.InitiatedByType | Should -Be 'Application'
        $App.ClientIP | Should -BeNullOrEmpty
        $App.Targets | Should -Be 'Sales'
    }

    It 'reports partial only when the batch helper flags a failed continuation page - a full page is not a cap' {
        $script:TargetFixture = @(1..999 | ForEach-Object { Get-AuditFixture -Id "a$_" -Activity 'Update group' })
        $script:TargetNextLink = 'https://graph.microsoft.com/v1.0/auditLogs/directoryAudits?$skiptoken=abc'
        $Result = Get-CIPPBecDirectoryAudits -TenantFilter 'contoso.com' -UserId $script:UserId -StartDate $script:Start -Heuristics $script:Heuristics
        $Result.Complete | Should -BeTrue -Because 'the helper already merged every continuation page into the response'
        $Result.Cap | Should -BeNullOrEmpty
        $Result.Count | Should -Be 999

        $script:TargetFixture = @(Get-AuditFixture -Id 'a1' -Activity 'Update group')
        Mock New-GraphBulkRequest {
            foreach ($R in (Invoke-FakeBulk -Requests $Requests)) {
                if ($R.id -eq 'Target') {
                    $R | Add-Member -NotePropertyName 'PagingIncomplete' -NotePropertyValue $true -Force
                    $R | Add-Member -NotePropertyName 'PagingError' -NotePropertyValue 'continuation page returned 429' -Force
                }
                $R
            }
        }
        $Result = Get-CIPPBecDirectoryAudits -TenantFilter 'contoso.com' -UserId $script:UserId -StartDate $script:Start -Heuristics $script:Heuristics
        $Result.Complete | Should -BeFalse
        $Result.Cap | Should -Be 'Target query: continuation page returned 429'
        $Result.Error | Should -BeNullOrEmpty
        $Result.Count | Should -Be 1
    }

    It 'reports a failed or missing direction as an error while keeping the rows from the other direction' {
        $script:TargetStatus = 403
        $script:ActorFixture = @(Get-AuditFixture -Id 'a9' -Activity 'Update group')
        $Result = Get-CIPPBecDirectoryAudits -TenantFilter 'contoso.com' -UserId $script:UserId -StartDate $script:Start -Heuristics $script:Heuristics
        $Result.Complete | Should -BeFalse
        $Result.Error | Should -Be 'Target query: Insufficient privileges'
        $Result.Cap | Should -BeNullOrEmpty
        $Result.Count | Should -Be 1
        $Result.Data[0].Id | Should -Be 'a9'

        $script:TargetStatus = 200
        $script:TargetMissing = $true
        $Result = Get-CIPPBecDirectoryAudits -TenantFilter 'contoso.com' -UserId $script:UserId -StartDate $script:Start -Heuristics $script:Heuristics
        $Result.Complete | Should -BeFalse
        $Result.Error | Should -Be 'Target query returned no response'
        $Result.Count | Should -Be 1
    }

    It 'lets a batch transport failure propagate to the caller instead of reporting an empty audit list' {
        Mock New-GraphBulkRequest { throw 'Graph batch unavailable' }
        { Get-CIPPBecDirectoryAudits -TenantFilter 'contoso.com' -UserId $script:UserId -StartDate $script:Start -Heuristics $script:Heuristics } | Should -Throw -ExpectedMessage '*Graph batch unavailable*'
    }
}
