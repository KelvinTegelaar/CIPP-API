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
