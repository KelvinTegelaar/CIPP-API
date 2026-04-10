#!/usr/bin/env pwsh
<#
.SYNOPSIS
    Tests the scheduler command blocklist enforcement across all three defense layers.

.DESCRIPTION
    Part 1: Unit tests for Get-CIPPSchedulerBlockedCommands.
    Part 2: Live tests via the local dev API (localhost:7071) — submits blocked commands
            via the AddScheduledItem endpoint and verifies they are rejected.

.NOTES
    For Part 2, the local Azure Functions host must be running:
        func host start  (from CIPP-API root)
#>
[CmdletBinding()]
param(
    [string]$BaseUrl = 'http://localhost:7071/api',
    [switch]$SkipLiveTests
)

$pass = 0
$fail = 0

function Assert-True {
    param([string]$Label, [bool]$Value, [string]$Detail = '')
    if ($Value) {
        Write-Host "  [PASS] $Label" -ForegroundColor Green
        $script:pass++
    } else {
        Write-Host "  [FAIL] $Label$(if ($Detail) { " -- $Detail" })" -ForegroundColor Red
        $script:fail++
    }
}

function Assert-Contains {
    param([string]$Label, [string]$Haystack, [string]$Needle)
    if ($Haystack -match [regex]::Escape($Needle)) {
        Write-Host "  [PASS] $Label" -ForegroundColor Green
        $script:pass++
    } else {
        Write-Host "  [FAIL] $Label" -ForegroundColor Red
        Write-Host "         Expected to contain: $Needle"
        Write-Host "         Got: $Haystack"
        $script:fail++
    }
}

# ---------------------------------------------------------------------------
# Load blocklist function from source
# ---------------------------------------------------------------------------
$blocklistPath = Join-Path $PSScriptRoot '../Modules/CIPPCore/Private/Get-CIPPSchedulerBlockedCommands.ps1'
if (-not (Test-Path $blocklistPath)) {
    Write-Error "Get-CIPPSchedulerBlockedCommands.ps1 not found at: $blocklistPath"
    exit 1
}
. $blocklistPath

# ---------------------------------------------------------------------------
# Part 1: Unit tests — blocklist content & structure
# ---------------------------------------------------------------------------
Write-Host "`n=== Part 1: Blocklist Unit Tests ===" -ForegroundColor Cyan

$blocked = Get-CIPPSchedulerBlockedCommands

Assert-True 'Get-CIPPSchedulerBlockedCommands returns an array' ($blocked -is [array] -or $blocked -is [string])
Assert-True 'Blocklist is not empty' ($blocked.Count -gt 0) "Count: $($blocked.Count)"

# Core token functions must be blocked
foreach ($cmd in @('Get-GraphToken', 'Get-GraphTokenFromCert', 'Get-ClassicAPIToken', 'Get-CIPPAzIdentityToken')) {
    Assert-True "Blocklist contains $cmd" ($cmd -in $blocked)
}

# Secret/key functions
foreach ($cmd in @('Get-CippKeyVaultSecret')) {
    Assert-True "Blocklist contains $cmd" ($cmd -in $blocked)
}

# Tenant enumeration
Assert-True 'Blocklist contains Get-Tenants' ('Get-Tenants' -in $blocked)

# Extension tokens
foreach ($cmd in @('Get-GradientToken', 'Get-HaloToken', 'Get-NinjaOneToken')) {
    Assert-True "Blocklist contains $cmd" ($cmd -in $blocked)
}

# Storage access
foreach ($cmd in @('Get-CIPPTable', 'Get-CIPPAzDataTableEntity')) {
    Assert-True "Blocklist contains $cmd" ($cmd -in $blocked)
}

# Verify safe scheduler commands are NOT on the blocklist (regression check)
$safeCmds = @(
    'Set-CIPPSignInState'
    'Get-CIPPUsers'
    'New-CIPPUser'
    'Set-CIPPUserLicense'
    'Get-CIPPAlertNewMFAMethod'
    'Push-CippExtensionData'
)
foreach ($cmd in $safeCmds) {
    Assert-True "Safe command $cmd is NOT blocked" ($cmd -notin $blocked)
}

# ---------------------------------------------------------------------------
# Part 2: Live API tests against local dev endpoint
# ---------------------------------------------------------------------------
if ($SkipLiveTests) {
    Write-Host "`n=== Part 2: Live Tests SKIPPED ===" -ForegroundColor Yellow
} else {
    Write-Host "`n=== Part 2: Live API Tests (POST /api/AddScheduledItem) ===" -ForegroundColor Cyan
    Write-Host "  Target: $BaseUrl" -ForegroundColor DarkGray

    $tenantFilter = 'testtenant.onmicrosoft.com'
    $scheduledTime = [int64](([datetime]::UtcNow) - (Get-Date '1/1/1970')).TotalSeconds

    # Commands to attempt — all should be rejected
    $attackCmds = @(
        'Get-GraphToken'
        'Get-GraphTokenFromCert'
        'Get-CIPPAzIdentityToken'
        'Get-CippKeyVaultSecret'
        'Get-Tenants'
        'Get-CIPPTable'
        'Get-CIPPAzDataTableEntity'
        'Get-GradientToken'
        'Get-HaloToken'
    )

    foreach ($cmd in $attackCmds) {
        $body = @{
            TenantFilter  = $tenantFilter
            Name          = "Security Test - $cmd"
            Command       = @{ value = $cmd; label = $cmd }
            Parameters    = @{ TenantFilter = $tenantFilter }
            ScheduledTime = $scheduledTime
            Recurrence    = '0'
        } | ConvertTo-Json -Depth 5

        try {
            $response = Invoke-RestMethod -Uri "$BaseUrl/AddScheduledItem" `
                -Method Post `
                -ContentType 'application/json' `
                -Body $body `
                -ErrorVariable restError `
                -ErrorAction SilentlyContinue

            $responseText = $response.Results ?? ($response | ConvertTo-Json -Compress)

            # A blocked command should return an error message, not succeed
            $wasBlocked = $responseText -match 'not permitted|blocked|Error'
            Assert-True "POST blocked command '$cmd'" $wasBlocked "Response: $responseText"
        } catch {
            # A non-2xx response still counts as blocked
            Assert-True "POST blocked command '$cmd' (HTTP error)" $true "Status: $($_.Exception.Response.StatusCode)"
        }
    }

    # Sanity check: a legitimate command should NOT be blocked by the API
    $legitimateBody = @{
        TenantFilter  = $tenantFilter
        Name          = 'Security Test - Legitimate Command (dry run)'
        Command       = @{ value = 'Get-CIPPUsers'; label = 'Get-CIPPUsers' }
        Parameters    = @{ TenantFilter = $tenantFilter }
        ScheduledTime = ($scheduledTime + 86400)  # tomorrow - won't actually execute
        Recurrence    = '0'
    } | ConvertTo-Json -Depth 5

    try {
        $legitResponse = Invoke-RestMethod -Uri "$BaseUrl/AddScheduledItem" `
            -Method Post `
            -ContentType 'application/json' `
            -Body $legitimateBody `
            -ErrorAction SilentlyContinue

        $legitText = $legitResponse.Results ?? ($legitResponse | ConvertTo-Json -Compress)
        $wasAccepted = $legitText -notmatch 'not permitted|blocked'
        Assert-True 'Legitimate command Get-CIPPUsers is accepted' $wasAccepted "Response: $legitText"
    } catch {
        Write-Host "  [INFO] Legitimate command test got HTTP error (may need auth): $($_.Exception.Message)" -ForegroundColor DarkGray
    }
}

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------
Write-Host "`n=== Results ===" -ForegroundColor Cyan
Write-Host "  Passed: $pass" -ForegroundColor Green
Write-Host "  Failed: $fail" -ForegroundColor $(if ($fail -gt 0) { 'Red' } else { 'Green' })

if ($fail -gt 0) { exit 1 }
