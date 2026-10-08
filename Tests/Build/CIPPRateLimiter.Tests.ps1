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

    It 'costs each $batch sub-request and blocks only the throttled sub-request endpoint' {
        $A = Get-AuthHeader 'tenant-a'
        $Body = @{ requests = @(
                @{ id = '1'; method = 'GET'; url = '/users/u1/authentication/methods' }
                @{ id = '2'; method = 'GET'; url = '/groups/6f1d2c3e-0000-4000-8000-0000000000a1/members' }
            ) } | ConvertTo-Json -Depth 5
        $Claim = [CIPP.CIPPRateLimiter]::Acquire('https://graph.microsoft.com/v1.0/$batch', 'POST', $Body, $A)
        $Response = '{"responses":[{"id":"1","status":200,"body":{}},{"id":"2","status":429,"headers":{"Retry-After":"20"}}]}'
        [CIPP.CIPPRateLimiter]::Observe($Claim, 200, (Get-ResponseHeader), $Response)

        [CIPP.CIPPRateLimiter]::Acquire('https://graph.microsoft.com/v1.0/groups/6f1d2c3e-0000-4000-8000-0000000000a2/members', 'GET', $null, $A).Wait.TotalSeconds | Should -BeGreaterThan 19
        [CIPP.CIPPRateLimiter]::Acquire('https://graph.microsoft.com/v1.0/users/u2/authentication/methods', 'GET', $null, $A).Wait | Should -Be ([timespan]::Zero)
    }

    It 'counts every EXO batch sub-request against the tenant budget' {
        $A = Get-AuthHeader 'tenant-a'
        $Body = @{ requests = @(1..10 | ForEach-Object { @{ id = "$_"; method = 'POST'; url = 'https://outlook.office365.com/adminapi/beta/tenant-a/InvokeCommand' } }) } | ConvertTo-Json -Depth 5
        $Batch = 'https://outlook.office365.com/adminapi/beta/tenant-a/$batch'
        1..30 | ForEach-Object { [CIPP.CIPPRateLimiter]::Acquire($Batch, 'POST', $Body, $A).Wait | Should -Be ([timespan]::Zero) }
        [CIPP.CIPPRateLimiter]::Acquire($Batch, 'POST', $Body, $A).Wait.TotalMilliseconds | Should -BeGreaterThan 100
    }
}
