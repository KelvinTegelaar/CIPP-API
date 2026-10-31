# New-GraphGetRequest and New-GraphPOSTRequest retry throttling and transient failures. A network failure
# ("Resource temporarily unavailable") has no HTTP response, and reading Retry-After from it threw
# "Cannot index into a null array" inside the catch, so the request failed instead of being retried.
# Retry-After may also be an HTTP date rather than seconds, which must fall back to the default wait.

BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
    Add-Type -Path (Join-Path $RepoRoot 'Shared/CIPPSharp/bin/CIPPSharp.dll')

    function Invoke-CIPPRestMethod { param($Uri, $Method, $Headers, $ContentType, $Body, $ResponseHeadersVariable, $StatusCodeVariable, [switch]$SkipHttpErrorCheck) }
    function Get-CIPPTextReplacement { param($TenantFilter, $Text, [switch]$EscapeForJson) $Text }

    . (Join-Path $RepoRoot 'Modules/CIPPCore/Public/GraphHelper/New-GraphGetRequest.ps1')
    . (Join-Path $RepoRoot 'Modules/CIPPCore/Public/GraphHelper/New-GraphPOSTRequest.ps1')

    function New-HttpFailure([int]$Status, [string]$RetryAfter) {
        $Headers = [System.Collections.Generic.Dictionary[string, string[]]]::new()
        if ($RetryAfter) { $Headers['Retry-After'] = [string[]]@($RetryAfter) }
        [CIPP.CIPPHttpRequestException]::new("Response status code does not indicate success: $Status", $Status, $Headers, '')
    }

    $script:Headers = @{ Authorization = 'Bearer test'; 'User-Agent' = 'test' }
}

Describe 'Graph request retries' -ForEach @(
    @{ Name = 'New-GraphGetRequest'; Call = { New-GraphGetRequest -uri 'https://graph.microsoft.com/beta/users' -tenantid 'contoso.com' -NoAuthCheck $true -Headers $script:Headers } }
    @{ Name = 'New-GraphPOSTRequest'; Call = { New-GraphPOSTRequest -uri 'https://graph.microsoft.com/beta/users' -tenantid 'contoso.com' -body '{}' -NoAuthCheck $true -headers $script:Headers } }
) {
    BeforeEach {
        $script:Calls = 0
        Mock -CommandName Start-Sleep -MockWith { }
    }

    It '<Name> retries a network failure that has no HTTP response' {
        Mock -CommandName Invoke-CIPPRestMethod -MockWith {
            $script:Calls++
            if ($script:Calls -eq 1) { throw [System.Net.Http.HttpRequestException]::new('Resource temporarily unavailable (graph.microsoft.com:443)') }
            [PSCustomObject]@{ value = @([PSCustomObject]@{ id = 'ok' }) }
        }

        $Result = & $Call

        $script:Calls | Should -Be 2
        @($Result.value ?? $Result)[0].id | Should -Be 'ok'
        Should -Invoke Start-Sleep -Times 1
    }

    It '<Name> waits the Retry-After seconds on a 429' {
        Mock -CommandName Invoke-CIPPRestMethod -MockWith {
            $script:Calls++
            if ($script:Calls -eq 1) { throw (New-HttpFailure 429 '7') }
            [PSCustomObject]@{ value = @() }
        }

        $null = & $Call

        $script:Calls | Should -Be 2
        Should -Invoke Start-Sleep -Times 1 -ParameterFilter { $Seconds -eq 7 }
    }

    It '<Name> falls back to the default wait when Retry-After is a date' {
        Mock -CommandName Invoke-CIPPRestMethod -MockWith {
            $script:Calls++
            if ($script:Calls -eq 1) { throw (New-HttpFailure 503 'Wed, 21 Oct 2026 07:28:00 GMT') }
            [PSCustomObject]@{ value = @() }
        }

        $null = & $Call

        $script:Calls | Should -Be 2
        Should -Invoke Start-Sleep -Times 1 -ParameterFilter { $Seconds -ge 1 -and $Seconds -le 4 }
    }
}
