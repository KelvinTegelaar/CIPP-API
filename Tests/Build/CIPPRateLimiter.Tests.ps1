BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
    Add-Type -Path (Join-Path $RepoRoot 'Shared/CIPPSharp/bin/CIPPSharp.dll')

    function Get-AuthHeader([string]$TenantId) {
        $Payload = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes("{`"tid`":`"$TenantId`"}")).TrimEnd('=').Replace('+', '-').Replace('/', '_')
        $Headers = [System.Collections.Generic.Dictionary[string, string]]::new([System.StringComparer]::OrdinalIgnoreCase)
        $Headers['Authorization'] = "Bearer eyJhbGciOiJub25lIn0.$Payload.sig"
        , $Headers
    }
    function Get-ResponseHeader([int]$RetryAfter) {
        $H = [System.Collections.Generic.Dictionary[string, string[]]]::new([System.StringComparer]::OrdinalIgnoreCase)
        if ($RetryAfter) { $H['Retry-After'] = @("$RetryAfter") }
        , $H
    }
    $Evaluate = 'https://graph.microsoft.com/v1.0/identity/conditionalAccess/evaluate'
}

Describe 'CIPPRateLimiter' {
    BeforeEach { [CIPP.CIPPRateLimiter]::Reset() }

    It 'ignores requests without a bearer token' {
        [CIPP.CIPPRateLimiter]::Acquire($Evaluate, 'POST', '{}', $null) | Should -BeNullOrEmpty
    }

    It 'lets a burst through and then spaces a measured budget per tenant' {
        $A = Get-AuthHeader 'tenant-a'
        $Waits = 1..12 | ForEach-Object { [CIPP.CIPPRateLimiter]::Acquire($Evaluate, 'POST', '{}', $A).Wait.TotalMilliseconds }
        $Waits[0..9] | ForEach-Object { $_ | Should -Be 0 }
        $Waits[10] | Should -BeGreaterThan 1000
        $Waits[11] | Should -BeGreaterThan $Waits[10]
        [CIPP.CIPPRateLimiter]::Acquire($Evaluate, 'POST', '{}', (Get-AuthHeader 'tenant-b')).Wait | Should -Be ([timespan]::Zero)
    }

    It 'shares a 429 Retry-After with later callers of the same tenant and endpoint only' {
        $A = Get-AuthHeader 'tenant-a'
        $Uri = 'https://graph.microsoft.com/v1.0/users/0b1c8f1e-0000-4000-8000-000000000001/memberOf'
        $Claim = [CIPP.CIPPRateLimiter]::Acquire($Uri, 'GET', $null, $A)
        $Claim.Wait | Should -Be ([timespan]::Zero)
        [CIPP.CIPPRateLimiter]::Observe($Claim, 429, (Get-ResponseHeader 10), '')

        $Other = 'https://graph.microsoft.com/v1.0/users/john@contoso.com/memberOf'
        [CIPP.CIPPRateLimiter]::Acquire($Other, 'GET', $null, $A).Wait.TotalSeconds | Should -BeGreaterThan 9
        [CIPP.CIPPRateLimiter]::Acquire($Other, 'GET', $null, (Get-AuthHeader 'tenant-b')).Wait | Should -Be ([timespan]::Zero)
        [CIPP.CIPPRateLimiter]::Acquire('https://graph.microsoft.com/v1.0/groups', 'GET', $null, $A).Wait | Should -Be ([timespan]::Zero)
    }

    It 'spaces the identity reports at 5 sub-requests per 10 seconds per tenant after a burst of 10, sign-ins and audits sharing it' {
        $A = Get-AuthHeader 'tenant-a'
        $Batch = { param($Urls) @{ requests = @($Urls | ForEach-Object -Begin { $n = 0 } -Process { @{ id = "$((++$n))"; method = 'GET'; url = $_ } }) } | ConvertTo-Json -Depth 5 }
        $Ten = @(1..8 | ForEach-Object { 'auditLogs/signIns?$top=1' }) + @('auditLogs/directoryAudits', 'reports/authenticationMethods/userRegistrationDetails')
        [CIPP.CIPPRateLimiter]::Acquire('https://graph.microsoft.com/beta/$batch', 'POST', (& $Batch $Ten), $A).Wait | Should -Be ([timespan]::Zero) -Because 'the first ten fit the burst'
        $Next = [CIPP.CIPPRateLimiter]::Acquire('https://graph.microsoft.com/beta/$batch', 'POST', (& $Batch @('auditLogs/signIns', 'auditLogs/signIns')), $A).Wait.TotalSeconds
        $Next | Should -BeGreaterThan 3
        $Next | Should -BeLessOrEqual 4.1
        [CIPP.CIPPRateLimiter]::Acquire('https://graph.microsoft.com/beta/auditLogs/signIns', 'GET', $null, (Get-AuthHeader 'tenant-b')).Wait | Should -Be ([timespan]::Zero)
        [CIPP.CIPPRateLimiter]::Acquire('https://graph.microsoft.com/beta/reports/getOffice365ActiveUserDetail(period=''D7'')', 'GET', $null, $A).Wait | Should -Be ([timespan]::Zero) -Because 'usage reports have their own limits'
    }

    It 'tells a batch caller the burst of the budget a sub-request falls under' {
        $Reports = [CIPP.CIPPRateLimiter]::BatchBudgetFor("auditLogs/signIns?`$filter=createdDateTime ge 2026-10-01T00:00:00Z&`$top=999", 'beta')
        $Reports.Name | Should -Be 'entra-reports'
        $Reports.Burst | Should -Be 10
        [CIPP.CIPPRateLimiter]::BatchBudgetFor('/reports/credentialUserRegistrationDetails', 'beta').Burst | Should -Be 10
        [CIPP.CIPPRateLimiter]::BatchBudgetFor('identity/conditionalAccess/evaluate', 'v1.0').Name | Should -Be 'ca-service'
        [CIPP.CIPPRateLimiter]::BatchBudgetFor('users/u1/memberOf', 'v1.0') | Should -BeNullOrEmpty
        [CIPP.CIPPRateLimiter]::BatchBudgetFor('reports/getOffice365ActiveUserDetail(period=''D7'')', 'beta') | Should -BeNullOrEmpty
    }
    It 'holds back a claim that was scheduled before the key got throttled' {
        $A = Get-AuthHeader 'tenant-a'
        $Early = [CIPP.CIPPRateLimiter]::Acquire($Evaluate, 'POST', '{}', $A)
        [CIPP.CIPPRateLimiter]::Recheck($Early) | Should -Be ([timespan]::Zero)
        $Throttled = [CIPP.CIPPRateLimiter]::Acquire($Evaluate, 'POST', '{}', $A)
        [CIPP.CIPPRateLimiter]::Observe($Throttled, 429, (Get-ResponseHeader 10), '')
        [CIPP.CIPPRateLimiter]::Recheck($Early).TotalSeconds | Should -BeGreaterThan 9
    }

    It 'costs each $batch sub-request and blocks only the throttled sub-request endpoint (<Form> body)' -ForEach @(
        @{ Form = 'string' }
        @{ Form = 'utf8' }
        @{ Form = 'utf8 with BOM' }
    ) {
        $A = Get-AuthHeader 'tenant-a'
        $Body = @{ requests = @(
                @{ id = '1'; method = 'GET'; url = '/users/u1/authentication/methods' }
                @{ id = '2'; method = 'GET'; url = '/groups/6f1d2c3e-0000-4000-8000-0000000000a1/members' }
            ) } | ConvertTo-Json -Depth 5
        $Claim = [CIPP.CIPPRateLimiter]::Acquire('https://graph.microsoft.com/v1.0/$batch', 'POST', $Body, $A)
        $Response = '{"responses":[{"id":"1","status":200,"body":{}},{"id":"2","status":429,"headers":{"Retry-After":"20"}}]}'
        $Bytes = [Text.Encoding]::UTF8.GetBytes($Response)
        if ($Form -eq 'string') { [CIPP.CIPPRateLimiter]::Observe($Claim, 200, (Get-ResponseHeader), $Response) }
        elseif ($Form -eq 'utf8') { [CIPP.CIPPRateLimiter]::Observe($Claim, 200, (Get-ResponseHeader), [byte[]]$Bytes) }
        else { [CIPP.CIPPRateLimiter]::Observe($Claim, 200, (Get-ResponseHeader), [byte[]](@(0xEF, 0xBB, 0xBF) + $Bytes)) }

        [CIPP.CIPPRateLimiter]::Acquire('https://graph.microsoft.com/v1.0/groups/6f1d2c3e-0000-4000-8000-0000000000a2/members', 'GET', $null, $A).Wait.TotalSeconds | Should -BeGreaterThan 19
        [CIPP.CIPPRateLimiter]::Acquire('https://graph.microsoft.com/v1.0/users/u2/authentication/methods', 'GET', $null, $A).Wait | Should -Be ([timespan]::Zero)
    }

    It 'holds every SharePoint endpoint of the tenant when one of them is throttled' {
        $A = Get-AuthHeader 'tenant-a'
        $Claim = [CIPP.CIPPRateLimiter]::Acquire('https://contoso-admin.sharepoint.com/_vti_bin/client.svc/ProcessQuery', 'POST', '<Request />', $A)
        [CIPP.CIPPRateLimiter]::Observe($Claim, 429, (Get-ResponseHeader 60), '429 TOO MANY REQUESTS')

        foreach ($Uri in @(
                'https://graph.microsoft.com/v1.0/sites/root'
                'https://graph.microsoft.com/beta/drives/b!abc/root/children'
                'https://graph.microsoft.com/v1.0/users/john@contoso.com/drive/root'
                'https://graph.microsoft.com/v1.0/groups/6f1d2c3e-0000-4000-8000-0000000000a1/sites/root'
                'https://contoso.sharepoint.com/sites/hr/_api/web'
                'https://contoso-my.sharepoint.com/personal/john/_vti_bin/sites.asmx'
            )) {
            [CIPP.CIPPRateLimiter]::Acquire($Uri, 'GET', $null, $A).Wait.TotalSeconds | Should -BeGreaterThan 59 -Because $Uri
        }
        [CIPP.CIPPRateLimiter]::Acquire('https://graph.microsoft.com/v1.0/users/john@contoso.com', 'GET', $null, $A).Wait | Should -Be ([timespan]::Zero)
        [CIPP.CIPPRateLimiter]::Acquire('https://graph.microsoft.com/v1.0/sites/root', 'GET', $null, (Get-AuthHeader 'tenant-b')).Wait | Should -Be ([timespan]::Zero)
    }

    It 'holds callers for a long SharePoint block instead of releasing them into it' {
        $A = Get-AuthHeader 'tenant-a'
        $Claim = [CIPP.CIPPRateLimiter]::Acquire('https://contoso-admin.sharepoint.com/_vti_bin/client.svc/ProcessQuery', 'POST', '<Request />', $A)
        [CIPP.CIPPRateLimiter]::Observe($Claim, 429, (Get-ResponseHeader 280), '429 TOO MANY REQUESTS')
        [CIPP.CIPPRateLimiter]::Acquire('https://graph.microsoft.com/v1.0/sites/root', 'GET', $null, $A).Wait.TotalSeconds | Should -BeGreaterThan 279
        [CIPP.CIPPRateLimiter]::MaxWait.TotalSeconds | Should -BeGreaterThan 300
    }

    It 'holds the SharePoint admin endpoint when a Graph $batch sites sub-request is throttled' {
        $A = Get-AuthHeader 'tenant-a'
        $Body = @{ requests = @(@{ id = '1'; method = 'GET'; url = '/sites/contoso.sharepoint.com:/sites/hr' }) } | ConvertTo-Json -Depth 5
        $Claim = [CIPP.CIPPRateLimiter]::Acquire('https://graph.microsoft.com/v1.0/$batch', 'POST', $Body, $A)
        [CIPP.CIPPRateLimiter]::Observe($Claim, 200, (Get-ResponseHeader), '{"responses":[{"id":"1","status":429,"headers":{"Retry-After":"30"}}]}')

        [CIPP.CIPPRateLimiter]::Acquire('https://contoso-admin.sharepoint.com/_vti_bin/client.svc/ProcessQuery', 'POST', '<Request />', $A).Wait.TotalSeconds | Should -BeGreaterThan 29
    }

    Context 'SharePoint resource-unit pacing' {
        BeforeAll {
            $Csom = 'https://contoso-admin.sharepoint.com/_vti_bin/client.svc/ProcessQuery'
            $SiteRead = '<Request><ObjectPaths><Method Name="GetSitePropertiesByUrl" /></ObjectPaths></Request>'
            $Write = '<Request><Actions><SetProperty Id="1" ObjectPathId="2" Name="SharingCapability" /></Actions></Request>'
            function Get-Wait($Uri, $Body, $Auth) { [CIPP.CIPPRateLimiter]::Acquire($Uri, 'POST', $Body, $Auth).Wait }
            function Get-SharePointBucket { @([CIPP.CIPPRateLimiter]::GetDiagnostics().Buckets).Where({ $_.Key -like '*|sharepoint' }, 'First')[0] }
        }

        It 'lets 150 units through, then waits: 25 site reads at 6 units, 150 Graph reads at 1' {
            $A = Get-AuthHeader 'tenant-a'
            # The bucket refills 18 units/s while the claims are made, so assert either side of the boundary.
            1..23 | ForEach-Object { Get-Wait $Csom $SiteRead $A | Should -Be ([timespan]::Zero) }
            @(1..7 | ForEach-Object { Get-Wait $Csom $SiteRead $A })[-1] | Should -BeGreaterThan ([timespan]::Zero)

            $B = Get-AuthHeader 'tenant-b'
            1..140 | ForEach-Object { [CIPP.CIPPRateLimiter]::Acquire('https://graph.microsoft.com/v1.0/sites/root', 'GET', $null, $B).Wait | Should -Be ([timespan]::Zero) }
            @(1..60 | ForEach-Object { [CIPP.CIPPRateLimiter]::Acquire('https://graph.microsoft.com/v1.0/sites/root', 'GET', $null, $B).Wait })[-1] | Should -BeGreaterThan ([timespan]::Zero)
        }

        It 'charges CSOM writes 20 and Graph permissions 5 from the same tenant budget' {
            $A = Get-AuthHeader 'tenant-a'
            1..7 | ForEach-Object { Get-Wait $Csom $Write $A | Should -Be ([timespan]::Zero) }
            @(1..3 | ForEach-Object { Get-Wait $Csom $Write $A })[-1] | Should -BeGreaterThan ([timespan]::Zero)

            $B = Get-AuthHeader 'tenant-b'
            1..30 | ForEach-Object { [CIPP.CIPPRateLimiter]::Acquire('https://graph.microsoft.com/v1.0/drives/b!x/items/01AB/permissions', 'GET', $null, $B).Wait | Should -Be ([timespan]::Zero) }
            @(1..10 | ForEach-Object { [CIPP.CIPPRateLimiter]::Acquire('https://contoso.sharepoint.com/_api/web', 'GET', $null, $B).Wait })[-1] | Should -BeGreaterThan ([timespan]::Zero)
        }

        It 'raises the rate while callers keep waiting, but not on the first burst, and lowers it again on a 429' {
            $A = Get-AuthHeader 'tenant-a'
            1..30 | ForEach-Object { $null = Get-Wait $Csom $SiteRead $A }
            (Get-SharePointBucket).LearnedPerSecond | Should -BeNullOrEmpty

            # 30 s of waiting later, the next waiting claim probes 10% higher.
            $Buckets = [CIPP.CIPPRateLimiter].GetField('_buckets', [Reflection.BindingFlags]'NonPublic,Static').GetValue($null)
            $Bucket = $Buckets['tenant-a|sharepoint']
            $Bucket.GetType().GetField('LastRaise').SetValue($Bucket, [datetime]::UtcNow.AddSeconds(-31).Ticks)
            $null = Get-Wait $Csom $SiteRead $A
            (Get-SharePointBucket).LearnedPerSecond | Should -Be 19.8

            $Claim = [CIPP.CIPPRateLimiter]::Acquire('https://graph.microsoft.com/v1.0/sites/root', 'GET', $null, $A)
            [CIPP.CIPPRateLimiter]::Observe($Claim, 429, (Get-ResponseHeader 1), '')
            (Get-SharePointBucket).LearnedPerSecond | Should -Be 18
        }
    }

    It 'counts every EXO batch sub-request against the tenant budget, after a burst of 90% of the minute' {
        $A = Get-AuthHeader 'tenant-a'
        $Sub = 'https://outlook.office365.com/adminapi/beta/tenant-a/InvokeCommand'
        $Burst = @{ requests = @(1..2700 | ForEach-Object { @{ id = "$_"; method = 'POST'; url = $Sub } }) } | ConvertTo-Json -Depth 5
        $Body = @{ requests = @(1..10 | ForEach-Object { @{ id = "$_"; method = 'POST'; url = $Sub } }) } | ConvertTo-Json -Depth 5
        $Batch = 'https://outlook.office365.com/adminapi/beta/tenant-a/$batch'
        [CIPP.CIPPRateLimiter]::Acquire($Batch, 'POST', $Burst, $A).Wait | Should -Be ([timespan]::Zero)
        [CIPP.CIPPRateLimiter]::Acquire($Batch, 'POST', $Body, $A).Wait.TotalMilliseconds | Should -BeGreaterThan 100
    }

    Context 'EXO Rate-Limit budget headers' {
        BeforeAll {
            $Exo = 'https://outlook.office365.com/adminapi/beta/tenant-a/InvokeCommand'
            function Get-BudgetHeader([string]$Remaining, [string]$Reset) {
                $H = [System.Collections.Generic.Dictionary[string, string[]]]::new([System.StringComparer]::OrdinalIgnoreCase)
                $H['Rate-Limit-Limit'] = @('3000')
                $H['Rate-Limit-Remaining'] = @($Remaining)
                if ($Reset) { $H['Rate-Limit-Reset'] = @($Reset) }
                , $H
            }
            $InThirty = [DateTime]::UtcNow.AddSeconds(30).ToString('o')
        }

        It 'spreads what is left of the budget over the rest of the window instead of spending it at the measured rate' {
            $A = Get-AuthHeader 'tenant-a'
            $B = Get-AuthHeader 'tenant-b'
            $Body = @{ requests = @(1..10 | ForEach-Object { @{ id = "$_"; method = 'POST'; url = $Exo } }) } | ConvertTo-Json -Depth 5
            $Batch = 'https://outlook.office365.com/adminapi/beta/tenant-a/$batch'
            # 600 left, 30 s to go: 300 kept as the in-flight reserve, the other 300 paced at 10/s.
            $Claim = [CIPP.CIPPRateLimiter]::Acquire($Exo, 'POST', '{}', $A)
            [CIPP.CIPPRateLimiter]::Observe($Claim, 200, (Get-BudgetHeader '600' $InThirty), '{}')
            $Paced = 1..31 | ForEach-Object { [CIPP.CIPPRateLimiter]::Acquire($Batch, 'POST', $Body, $A).Wait.TotalMilliseconds }
            $Unpaced = 1..31 | ForEach-Object { [CIPP.CIPPRateLimiter]::Acquire($Batch, 'POST', $Body, $B).Wait.TotalMilliseconds }
            $Paced[-1] | Should -BeGreaterThan 800
            $Unpaced[-1] | Should -BeLessThan 400
        }

        It 'lifts the pace when a later response reports a healthy budget' {
            $A = Get-AuthHeader 'tenant-a'
            $Claim = [CIPP.CIPPRateLimiter]::Acquire($Exo, 'POST', '{}', $A)
            [CIPP.CIPPRateLimiter]::Observe($Claim, 200, (Get-BudgetHeader '310' $InThirty), '{}')
            # 10 usable over 30 s: the tenant is paced well below its measured rate first.
            $Paced = 1..15 | ForEach-Object { [CIPP.CIPPRateLimiter]::Acquire($Exo, 'POST', '{}', $A).Wait }
            $Paced[-1] | Should -BeGreaterThan ([timespan]::Zero)
            [CIPP.CIPPRateLimiter]::Observe($Claim, 200, (Get-BudgetHeader '2900' $InThirty), '{}')
            $Waits = 1..20 | ForEach-Object { [CIPP.CIPPRateLimiter]::Acquire($Exo, 'POST', '{}', $A).Wait }
            $Waits | ForEach-Object { $_ | Should -Be ([timespan]::Zero) }
        }

        It 'holds the tenant until the reset once the reserve itself is spent (<Overload> body)' -ForEach @(
            @{ Overload = 'string' }
            @{ Overload = 'bytes' }
        ) {
            $A = Get-AuthHeader 'tenant-a'
            $Claim = [CIPP.CIPPRateLimiter]::Acquire($Exo, 'POST', '{}', $A)
            $Headers = Get-BudgetHeader '250' $InThirty
            if ($Overload -eq 'string') { [CIPP.CIPPRateLimiter]::Observe($Claim, 200, $Headers, '{}') }
            else { [CIPP.CIPPRateLimiter]::Observe($Claim, 200, $Headers, [byte[]][Text.Encoding]::UTF8.GetBytes('{}')) }
            [CIPP.CIPPRateLimiter]::Acquire($Exo, 'POST', '{}', $A).Wait.TotalSeconds | Should -BeGreaterThan 25
            [CIPP.CIPPRateLimiter]::Acquire($Exo, 'POST', '{}', (Get-AuthHeader 'tenant-b')).Wait | Should -Be ([timespan]::Zero)
        }

        It 'holds a $batch caller on the budget header too' {
            $A = Get-AuthHeader 'tenant-a'
            $Body = @{ requests = @(1..10 | ForEach-Object { @{ id = "$_"; method = 'POST'; url = $Exo } }) } | ConvertTo-Json -Depth 5
            $Claim = [CIPP.CIPPRateLimiter]::Acquire('https://outlook.office365.com/adminapi/beta/tenant-a/$batch', 'POST', $Body, $A)
            [CIPP.CIPPRateLimiter]::Observe($Claim, 200, (Get-BudgetHeader '40' $InThirty), [byte[]][Text.Encoding]::UTF8.GetBytes('{"responses":[]}'))
            [CIPP.CIPPRateLimiter]::Acquire($Exo, 'POST', '{}', $A).Wait.TotalSeconds | Should -BeGreaterThan 25
        }

        It 'does not hold while the budget is healthy, or when the reset is missing or already past' -ForEach @(
            @{ Remaining = '2600'; Reset = 'future' }
            @{ Remaining = '10'; Reset = '' }
            @{ Remaining = '10'; Reset = 'past' }
        ) {
            $A = Get-AuthHeader 'tenant-a'
            $ResetValue = switch ($Reset) { 'future' { $InThirty } 'past' { [DateTime]::UtcNow.AddSeconds(-5).ToString('o') } default { '' } }
            $Claim = [CIPP.CIPPRateLimiter]::Acquire($Exo, 'POST', '{}', $A)
            [CIPP.CIPPRateLimiter]::Observe($Claim, 200, (Get-BudgetHeader $Remaining $ResetValue), '{}')
            [CIPP.CIPPRateLimiter]::Acquire($Exo, 'POST', '{}', $A).Wait | Should -Be ([timespan]::Zero)
        }

        It 'ignores budget headers on endpoints without a measured rule' {
            $A = Get-AuthHeader 'tenant-a'
            $Uri = 'https://graph.microsoft.com/v1.0/users/0b1c8f1e-0000-4000-8000-000000000001/memberOf'
            $Claim = [CIPP.CIPPRateLimiter]::Acquire($Uri, 'GET', $null, $A)
            [CIPP.CIPPRateLimiter]::Observe($Claim, 200, (Get-BudgetHeader '1' $InThirty), '{}')
            [CIPP.CIPPRateLimiter]::Acquire($Uri, 'GET', $null, $A).Wait | Should -Be ([timespan]::Zero)
        }
    }
}
