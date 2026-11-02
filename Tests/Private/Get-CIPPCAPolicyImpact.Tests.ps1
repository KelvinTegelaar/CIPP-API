# Pester tests for Get-CIPPCAPolicyImpact - per-policy sign-in impact built from auditLogs/signIns,
# read as 24 hour slices through $batch.

BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
    . (Join-Path $RepoRoot 'Modules/CIPPCore/Public/Get-CIPPCAPolicyImpact.ps1')

    function New-GraphGetRequest { param($uri, $tenantid, $AsApp, $ErrorAction, $noPagination, [switch]$ReturnRawResponse) }
    function New-GraphBulkRequest { param($Requests, $tenantid, $asapp, $Version, $ErrorAction) }

    $script:PolicyId = '9f6a6dc0-d117-4992-9f64-cab426e0085b'
    $script:OtherPolicyId = '088fe318-996f-467e-a6ee-729df9e83c36'

    function New-SignIn {
        param([string]$Created, [string]$Result, [string]$User = 'Alice', [string]$App = 'Azure Portal', [string]$Id = ([guid]::NewGuid().ToString()))
        [pscustomobject]@{
            id                               = $Id
            createdDateTime                  = $Created
            userDisplayName                  = $User
            userPrincipalName                = "$($User.ToLower())@contoso.com"
            userId                           = 'u-' + $User
            appDisplayName                   = $App
            appId                            = 'app-1'
            ipAddress                        = '203.0.113.5'
            clientAppUsed                    = 'Browser'
            status                           = [pscustomobject]@{ errorCode = 0; failureReason = 'Other.' }
            appliedConditionalAccessPolicies = @(
                [pscustomobject]@{ id = $script:OtherPolicyId; result = 'success'; conditionsSatisfied = 'application,users'; conditionsNotSatisfied = 'none'; enforcedGrantControls = @('Block'); enforcedSessionControls = @(); sessionControlsNotSatisfied = @() }
                [pscustomobject]@{ id = $script:PolicyId; result = $Result; conditionsSatisfied = 'application,users'; conditionsNotSatisfied = 'none'; enforcedGrantControls = @('Mfa'); enforcedSessionControls = @(); sessionControlsNotSatisfied = @() }
            )
        }
    }

    # Answers every request in a batch chunk with the same rows; real slices would each hold their own day.
    function New-BatchAnswer {
        param([object[]]$Requests, [object[]]$Value = @(), [int]$Status = 200)
        foreach ($Request in $Requests) {
            [pscustomobject]@{
                id      = $Request.id
                status  = $Status
                headers = @{}
                body    = if ($Status -ge 400) {
                    [pscustomobject]@{ error = [pscustomobject]@{ code = 'Authorization_RequestDenied'; message = 'Insufficient privileges' } }
                } else {
                    [pscustomobject]@{ value = @($Value) }
                }
            }
        }
    }

    $script:Yesterday = [datetime]::UtcNow.Date.AddDays(-1)
    $script:YesterdayKey = $script:Yesterday.ToString('yyyy-MM-dd')
    $script:TwoDaysAgoKey = $script:Yesterday.AddDays(-1).ToString('yyyy-MM-dd')
}

Describe 'Get-CIPPCAPolicyImpact' {
    BeforeEach {
        Mock -CommandName New-GraphGetRequest -MockWith {
            [pscustomobject]@{ id = $script:PolicyId; displayName = 'MFA for all'; state = 'enabled' }
        } -ParameterFilter { $uri -like '*/conditionalAccess/policies/*' }
        Mock -CommandName New-GraphBulkRequest -MockWith { New-BatchAnswer -Requests $Requests }
    }

    It 'rejects a policy id that is not a GUID before calling Graph' {
        { Get-CIPPCAPolicyImpact -TenantFilter 'contoso.com' -PolicyId 'not-a-guid or 1 eq 1' } | Should -Throw '*not a GUID*'
        Should -Invoke New-GraphGetRequest -Times 0
        Should -Invoke New-GraphBulkRequest -Times 0
    }

    It 'sends one 24 hour slice per day of the window, newest first, in batches of BatchSize' {
        $null = Get-CIPPCAPolicyImpact -TenantFilter 'contoso.com' -PolicyId $script:PolicyId -Days 30 -BatchSize 10

        Should -Invoke New-GraphBulkRequest -Times 3 -Exactly
        Should -Invoke New-GraphBulkRequest -Times 3 -ParameterFilter {
            @($Requests).Count -eq 10 -and $Version -eq 'beta' -and $tenantid -eq 'contoso.com'
        }
        Should -Invoke New-GraphBulkRequest -Times 1 -ParameterFilter {
            $First = [System.Uri]::UnescapeDataString($Requests[0].url)
            $Requests[0].id -eq '0' -and
            $First -like "*appliedConditionalAccessPolicies/any(p:p/id eq '$($script:PolicyId)')*" -and
            $First -match 'createdDateTime ge \S+ and createdDateTime lt \S+' -and
            $First -like '*$top=999*'
        }
    }

    It 'covers only its own ten day segment of a 30 day window' {
        $Result = Get-CIPPCAPolicyImpact -TenantFilter 'contoso.com' -PolicyId $script:PolicyId -Days 30 -SegmentIndex 2

        $Result.segmentIndex | Should -Be 2
        $Result.sliceCount | Should -Be 10
        ([datetime]$Result.endDateTime).ToUniversalTime().Date | Should -Be ([datetime]::UtcNow.AddDays(-20).Date)
        ([datetime]$Result.startDateTime).ToUniversalTime().Date | Should -Be ([datetime]::UtcNow.AddDays(-30).Date)
        $Result.days.Count | Should -BeIn @(10, 11)
        Should -Invoke New-GraphBulkRequest -Times 1 -Exactly
    }

    It 'clips the last segment to the window instead of reading past it' {
        $Result = Get-CIPPCAPolicyImpact -TenantFilter 'contoso.com' -PolicyId $script:PolicyId -Days 7 -SegmentIndex 0

        $Result.sliceCount | Should -Be 7
        ([datetime]$Result.startDateTime).ToUniversalTime() | Should -BeGreaterOrEqual ([datetime]::UtcNow.AddDays(-7).AddMinutes(-1))
    }

    It 'refuses a segment that starts outside the window' {
        { Get-CIPPCAPolicyImpact -TenantFilter 'contoso.com' -PolicyId $script:PolicyId -Days 7 -SegmentIndex 1 } | Should -Throw '*outside the 7 day window*'
    }

    It 'buckets sign-ins by UTC day using the result for this policy only' {
        Mock -CommandName New-GraphBulkRequest -MockWith {
            # Put every row on the first slice; the others are empty.
            $Answers = @(New-BatchAnswer -Requests $Requests)
            $Answers[0].body.value = @(
                (New-SignIn -Created "$($script:YesterdayKey)T10:00:00Z" -Result 'success'),
                (New-SignIn -Created "$($script:YesterdayKey)T11:00:00Z" -Result 'failure'),
                (New-SignIn -Created "$($script:YesterdayKey)T12:00:00Z" -Result 'notApplied'),
                (New-SignIn -Created "$($script:TwoDaysAgoKey)T12:00:00Z" -Result 'success')
            )
            $Answers
        }

        $Result = Get-CIPPCAPolicyImpact -TenantFilter 'contoso.com' -PolicyId $script:PolicyId -Days 7

        $Result.displayName | Should -Be 'MFA for all'
        $Result.source | Should -Be 'signInLogs'
        $Result.signInCount | Should -Be 4
        $Result.partial | Should -BeFalse
        $Result.days.Count | Should -Be 8
        $Yesterday = $Result.days | Where-Object date -EQ $script:YesterdayKey
        $Yesterday.success | Should -Be 1
        $Yesterday.failure | Should -Be 1
        $Yesterday.notApplied | Should -Be 1
        $Yesterday.total | Should -Be 3
        ($Result.days | Where-Object date -EQ $script:TwoDaysAgoKey).success | Should -Be 1
        $Result.totals.success | Should -Be 2
        $Result.totals.failure | Should -Be 1
        $Result.totals.total | Should -Be 4
        # The other policy reported success on every sign-in; that must not leak into this policy's counts.
        $Result.totals.notApplied | Should -Be 1
    }

    It 'folds a sign-in just after local midnight into the previous UTC day' {
        Mock -CommandName New-GraphBulkRequest -MockWith {
            $Answers = @(New-BatchAnswer -Requests $Requests)
            $Answers[0].body.value = @((New-SignIn -Created "$($script:YesterdayKey)T01:30:00+02:00" -Result 'success'))
            $Answers
        }

        $Result = Get-CIPPCAPolicyImpact -TenantFilter 'contoso.com' -PolicyId $script:PolicyId -Days 7

        ($Result.days | Where-Object date -EQ $script:TwoDaysAgoKey).success | Should -Be 1
        ($Result.days | Where-Object date -EQ $script:YesterdayKey).success | Should -Be 0
    }

    It 'keeps samples only for results where controls were not met, capped per day' {
        $Value = [System.Collections.Generic.List[object]]::new()
        1..5 | ForEach-Object { $Value.Add((New-SignIn -Created "$($script:YesterdayKey)T0$($_):00:00Z" -Result 'failure' -User "F$_")) }
        $Value.Add((New-SignIn -Created "$($script:YesterdayKey)T08:00:00Z" -Result 'reportOnlyInterrupted' -User 'Interrupted'))
        $Value.Add((New-SignIn -Created "$($script:YesterdayKey)T09:00:00Z" -Result 'success' -User 'Fine'))
        $Value.Add((New-SignIn -Created "$($script:YesterdayKey)T09:30:00Z" -Result 'reportOnlyNotApplied' -User 'Skipped'))
        $Value.Add((New-SignIn -Created "$($script:TwoDaysAgoKey)T09:00:00Z" -Result 'reportOnlyFailure' -User 'Older'))
        Mock -CommandName New-GraphBulkRequest -MockWith {
            $Answers = @(New-BatchAnswer -Requests $Requests)
            $Answers[0].body.value = $Value.ToArray()
            $Answers
        }

        $Result = Get-CIPPCAPolicyImpact -TenantFilter 'contoso.com' -PolicyId $script:PolicyId -Days 7 -SamplesPerDay 3

        $Result.samples.Count | Should -Be 4
        @($Result.samples | Where-Object day -EQ $script:YesterdayKey).Count | Should -Be 3
        ($Result.samples | Where-Object day -EQ $script:TwoDaysAgoKey).userDisplayName | Should -Be 'Older'
        $Result.samples.userDisplayName | Should -Not -Contain 'Fine'
        $Result.samples.userDisplayName | Should -Not -Contain 'Skipped'
        $Result.samples[0].policyResult | Should -BeIn @('failure', 'reportOnlyInterrupted')
        $Result.samples[0].enforcedGrantControls | Should -Contain 'Mfa'
        $Result.samples[0].conditionsSatisfied | Should -Be @('application', 'users')
        $Result.samples[0].conditionsNotSatisfied | Should -BeNullOrEmpty
        # Counts still include everything, samples do not change bucketing.
        $Result.totals.failure | Should -Be 5
        $Result.totals.reportOnlyNotApplied | Should -Be 1
    }

    It 'merges rows from every slice and every batch call' {
        Mock -CommandName New-GraphBulkRequest -MockWith {
            $Answers = @(New-BatchAnswer -Requests $Requests)
            foreach ($Answer in $Answers) {
                $Answer.body.value = @((New-SignIn -Created "$($script:YesterdayKey)T10:00:00Z" -Result 'success'))
            }
            $Answers
        }

        $Result = Get-CIPPCAPolicyImpact -TenantFilter 'contoso.com' -PolicyId $script:PolicyId -Days 30 -BatchSize 10

        $Result.signInCount | Should -Be 30
        $Result.batchCalls | Should -Be 3
        $Result.totals.success | Should -Be 30
    }

    It 'reports partial when a slice could not be paged to the end' {
        Mock -CommandName New-GraphBulkRequest -MockWith {
            $Answers = @(New-BatchAnswer -Requests $Requests)
            $Answers[1] | Add-Member -NotePropertyName PagingIncomplete -NotePropertyValue $true
            $Answers[1] | Add-Member -NotePropertyName PagingError -NotePropertyValue 'continuation page returned 429'
            $Answers
        }

        $Result = Get-CIPPCAPolicyImpact -TenantFilter 'contoso.com' -PolicyId $script:PolicyId -Days 7

        $Result.partial | Should -BeTrue
        $Result.partialReason | Should -Be 'continuation page returned 429'
    }

    It 'surfaces a Graph error status instead of counting an error body' {
        Mock -CommandName New-GraphBulkRequest -MockWith { New-BatchAnswer -Requests $Requests -Status 403 }

        { Get-CIPPCAPolicyImpact -TenantFilter 'contoso.com' -PolicyId $script:PolicyId -Days 7 } | Should -Throw '*403*Insufficient privileges*'
    }

    It 'returns a full zero-filled window when the policy was never evaluated' {
        $Result = Get-CIPPCAPolicyImpact -TenantFilter 'contoso.com' -PolicyId $script:PolicyId -Days 1

        $Result.signInCount | Should -Be 0
        $Result.sliceCount | Should -Be 1
        $Result.days.Count | Should -Be 2
        ($Result.days | Measure-Object -Property total -Sum).Sum | Should -Be 0
        $Result.samples.Count | Should -Be 0
        $Result.oldestSignInSeen | Should -BeNullOrEmpty
    }
}
