#!/usr/bin/env pwsh
<#
.SYNOPSIS
    Tests OData filter injection and the ConvertTo-CIPPODataFilterValue sanitization helper.

.DESCRIPTION
    Part 1: Unit tests for ConvertTo-CIPPODataFilterValue — verifies escaping/validation behavior.
    Part 2: Live injection tests against the local dev API (localhost:7071).

.NOTES
    Requires the local Azure Functions host to be running for Part 2.
    Run: func host start  (from CIPP-API root)
#>
[CmdletBinding()]
param(
    [string]$BaseUrl = 'http://localhost:7071/api',
    [switch]$SkipLiveTests
)

# ---------------------------------------------------------------------------
# Load the sanitization function from source
# ---------------------------------------------------------------------------
$helperPath = Join-Path $PSScriptRoot '../Modules/CIPPCore/Public/ConvertTo-CIPPODataFilterValue.ps1'
if (-not (Test-Path $helperPath)) {
    Write-Error "ConvertTo-CIPPODataFilterValue.ps1 not found at: $helperPath"
    exit 1
}
. $helperPath

$pass = 0
$fail = 0

function Assert-Equal {
    param([string]$Label, $Got, $Expected)
    if ($Got -eq $Expected) {
        Write-Host "  [PASS] $Label" -ForegroundColor Green
        $script:pass++
    } else {
        Write-Host "  [FAIL] $Label" -ForegroundColor Red
        Write-Host "         Expected: $Expected"
        Write-Host "         Got:      $Got"
        $script:fail++
    }
}

function Assert-Throws {
    param([string]$Label, [scriptblock]$Block)
    try {
        & $Block | Out-Null
        Write-Host "  [FAIL] $Label (expected throw, but did not)" -ForegroundColor Red
        $script:fail++
    } catch {
        Write-Host "  [PASS] $Label (threw: $($_.Exception.Message))" -ForegroundColor Green
        $script:pass++
    }
}

# ---------------------------------------------------------------------------
# Part 1: Unit tests — ConvertTo-CIPPODataFilterValue
# ---------------------------------------------------------------------------
Write-Host "`n=== Part 1: Sanitization Unit Tests ===" -ForegroundColor Cyan

Write-Host "`n-- String escaping --"
# Classic OData injection: single quote should be doubled
Assert-Equal 'Injection payload escaped' `
(ConvertTo-CIPPODataFilterValue -Value "' or PartitionKey ne '" -Type String) `
    "'' or PartitionKey ne ''"

Assert-Equal 'Normal string passthrough' `
(ConvertTo-CIPPODataFilterValue -Value 'hello world' -Type String) `
    'hello world'

Assert-Equal 'Multiple single quotes' `
(ConvertTo-CIPPODataFilterValue -Value "O'Brien's" -Type String) `
    "O''Brien''s"

Assert-Equal 'Empty string' `
(ConvertTo-CIPPODataFilterValue -Value '' -Type String) `
    ''

Write-Host "`n-- GUID validation --"
Assert-Equal 'Valid GUID' `
(ConvertTo-CIPPODataFilterValue -Value '12345678-1234-1234-1234-123456789abc' -Type Guid) `
    '12345678-1234-1234-1234-123456789abc'

Assert-Throws 'Invalid GUID throws' {
    ConvertTo-CIPPODataFilterValue -Value "' or '1' eq '1" -Type Guid
}
Assert-Throws 'GUID with extra chars throws' {
    ConvertTo-CIPPODataFilterValue -Value '12345678-1234-1234-1234-123456789abc; DROP' -Type Guid
}

Write-Host "`n-- Date validation --"
Assert-Equal 'Valid date yyyy-MM-dd' `
(ConvertTo-CIPPODataFilterValue -Value '2026-04-01' -Type Date) `
    '2026-04-01'

Assert-Equal 'Valid date yyyyMMdd' `
(ConvertTo-CIPPODataFilterValue -Value '20260401' -Type Date) `
    '20260401'

Assert-Equal 'Valid ISO 8601 datetime UTC' `
(ConvertTo-CIPPODataFilterValue -Value '2026-04-01T12:00:00Z' -Type Date) `
    '2026-04-01T12:00:00Z'

Assert-Equal 'Valid ISO 8601 datetime with offset' `
(ConvertTo-CIPPODataFilterValue -Value '2026-04-01T12:00:00+00:00' -Type Date) `
    '2026-04-01T12:00:00+00:00'

Assert-Throws 'Invalid date throws' {
    ConvertTo-CIPPODataFilterValue -Value "20260401' or '1' eq '1" -Type Date
}

Write-Host "`n-- Integer validation --"
Assert-Equal 'Valid integer' `
(ConvertTo-CIPPODataFilterValue -Value '42' -Type Integer) `
    '42'

Assert-Throws 'Integer with injection throws' {
    ConvertTo-CIPPODataFilterValue -Value '42 or 1 eq 1' -Type Integer
}

# ---------------------------------------------------------------------------
# Part 2: Live injection tests against local dev API
# ---------------------------------------------------------------------------
if ($SkipLiveTests) {
    Write-Host "`n=== Part 2: Live Tests (skipped) ===" -ForegroundColor Yellow
} else {
    Write-Host "`n=== Part 2: Live Injection Tests ($BaseUrl) ===" -ForegroundColor Cyan
    Write-Host "  Note: These require the local Functions host to be running.`n"

    $headers = @{
        'x-ms-client-principal' = [Convert]::ToBase64String(
            [Text.Encoding]::UTF8.GetBytes(
                '{"identityProvider":"aad","userId":"test","userDetails":"test@test.com","userRoles":["authenticated","superadmin"]}'
            )
        )
        'x-ms-client-principal-idp'  = 'aad'
        'x-ms-client-principal-name' = 'test@test.com'
    }

    function Invoke-TestRequest {
        param([string]$Label, [string]$Url, [int]$ExpectedStatus, [string]$ExpectedInjectionWarning = '')
        try {
            $response = Invoke-WebRequest -Uri $Url -Headers $headers -SkipHttpErrorCheck -ErrorAction Stop
            $statusOk = $response.StatusCode -eq $ExpectedStatus
            $symbol = if ($statusOk) { '[PASS]' } else { '[FAIL]' }
            $color = if ($statusOk) { 'Green' } else { 'Red' }
            Write-Host "  $symbol $Label (HTTP $($response.StatusCode))" -ForegroundColor $color
            if (-not $statusOk) { $script:fail++ } else { $script:pass++ }

            if ($ExpectedInjectionWarning -and $response.StatusCode -eq 200) {
                $body = $response.Content | ConvertFrom-Json -ErrorAction SilentlyContinue
                $count = if ($body -is [array]) { $body.Count } else { ($body | Measure-Object).Count }
                Write-Host "    -> Returned $count item(s) — $ExpectedInjectionWarning" -ForegroundColor Yellow
            }

            return $response
        } catch {
            Write-Host "  [SKIP] $Label — could not reach $BaseUrl ($($_.Exception.Message))" -ForegroundColor DarkYellow
        }
    }

    # Normal request — expect 404 for non-existent ID
    Invoke-TestRequest `
        -Label 'Normal: ListContactTemplates?ID=nonexistent -> 404' `
        -Url "$BaseUrl/ListContactTemplates?ID=nonexistent" `
        -ExpectedStatus 404

    # Injection attempt — with unpatched code this returns 200 + cross-partition data
    # With patched code (single quote doubled) it should return 404 (no match for escaped value)
    $injectionPayload = [Uri]::EscapeDataString("' or PartitionKey ne '")
    Invoke-TestRequest `
        -Label "Injection: ListContactTemplates?ID=' or PartitionKey ne ' -> should be 404 (patched)" `
        -Url "$BaseUrl/ListContactTemplates?ID=$injectionPayload" `
        -ExpectedStatus 404 `
        -ExpectedInjectionWarning 'INJECTION SUCCEEDED if >0 items returned'

    # Sanitized: normal-looking template ID (adjust to a real one in your test data if available)
    Invoke-TestRequest `
        -Label 'Sanitized: ListContactTemplates with valid name -> 200 or 404' `
        -Url "$BaseUrl/ListContactTemplates" `
        -ExpectedStatus 200
}

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------
Write-Host "`n=== Results ===" -ForegroundColor Cyan
Write-Host "  Passed: $pass" -ForegroundColor Green
Write-Host "  Failed: $fail" -ForegroundColor $(if ($fail -gt 0) { 'Red' } else { 'Green' })

if ($fail -gt 0) { exit 1 } else { exit 0 }
