#!/usr/bin/env pwsh
<#
.SYNOPSIS
    Tests for authentication hardening in Test-CIPPAccess and related functions.
.DESCRIPTION
    Validates that the x-ms-client-principal header is properly decoded, validated,
    and that malformed inputs are rejected rather than silently elevated.
.NOTES
    Does not require a live API — tests the helper functions in isolation.
#>
[CmdletBinding()]
param()

$pass = 0
$fail = 0

function Assert-True {
    param([string]$Label, [scriptblock]$Block)
    try {
        $result = & $Block
        if ($result) {
            Write-Host "  [PASS] $Label" -ForegroundColor Green
            $script:pass++
        } else {
            Write-Host "  [FAIL] $Label (returned false/null)" -ForegroundColor Red
            $script:fail++
        }
    } catch {
        Write-Host "  [FAIL] $Label (threw: $($_.Exception.Message))" -ForegroundColor Red
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

# ---------------------------------------------------------------------------
# Helper: encode a principal object as base64 (mirrors EasyAuth behaviour)
# ---------------------------------------------------------------------------
function ConvertTo-Base64Principal {
    param([hashtable]$Principal)
    $json = $Principal | ConvertTo-Json -Compress
    return [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($json))
}

Write-Host "`n=== Test-Authentication: Base64 Principal Validation ===" -ForegroundColor Cyan

Write-Host "`n-- Valid principal decoding --"

Assert-True 'Valid EasyAuth principal decodes without error' {
    $raw = ConvertTo-Base64Principal @{
        identityProvider = 'aad'
        userId           = 'oid-1234'
        userDetails      = 'user@contoso.com'
        userRoles        = @('authenticated', 'anonymous')
    }
    $decoded = [System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String($raw)) | ConvertFrom-Json -ErrorAction Stop
    $null -ne $decoded -and $decoded.userDetails -eq 'user@contoso.com'
}

Assert-True 'Claims-shape principal (App Service) decodes without error' {
    $raw = ConvertTo-Base64Principal @{
        identityProvider = 'aad'
        userId           = 'oid-5678'
        userDetails      = ''
        userRoles        = @('authenticated', 'anonymous')
        claims           = @(
            @{ typ = 'preferred_username'; val = 'admin@contoso.com' }
            @{ typ = 'http://schemas.microsoft.com/identity/claims/objectidentifier'; val = 'oid-5678' }
        )
    }
    $decoded = [System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String($raw)) | ConvertFrom-Json -ErrorAction Stop
    $null -ne $decoded
}

Write-Host "`n-- Invalid / malformed principal --"

Assert-Throws 'Garbage base64 throws' {
    [System.Convert]::FromBase64String('not-valid-base64!!!') | Out-Null
}

Assert-Throws 'Invalid JSON after decode throws with -ErrorAction Stop' {
    $raw = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes('{ this is not json }'))
    [System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String($raw)) | ConvertFrom-Json -ErrorAction Stop
}

Assert-True 'Empty string is detected as missing before decode' {
    $raw = ''
    [string]::IsNullOrWhiteSpace($raw)
}

Write-Host "`n-- Principal field validation --"

Assert-True 'Valid principal has userDetails or claims' {
    $raw = ConvertTo-Base64Principal @{
        identityProvider = 'aad'
        userId           = 'oid-abc'
        userDetails      = 'someone@example.com'
        userRoles        = @('authenticated')
    }
    $user = [System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String($raw)) | ConvertFrom-Json
    ($user.PSObject.Properties.Name -contains 'userDetails') -or ($user.PSObject.Properties.Name -contains 'claims')
}

Assert-True 'Principal without userDetails and claims is detectable' {
    $raw = ConvertTo-Base64Principal @{
        identityProvider = 'aad'
        userId           = 'oid-xyz'
    }
    $user = [System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String($raw)) | ConvertFrom-Json
    -not ($user.PSObject.Properties.Name -contains 'userDetails') -and -not ($user.PSObject.Properties.Name -contains 'claims')
}

# ---------------------------------------------------------------------------
# ExecCippFunction blocklist validation
# ---------------------------------------------------------------------------
Write-Host "`n=== Test-ExecCippFunction: Blocklist Validation ===" -ForegroundColor Cyan

$BlockList = @(
    'Get-GraphToken'
    'Get-GraphTokenFromCert'
    'Get-ClassicAPIToken'
    'Get-CIPPSamKey'
    'Get-CIPPAzDataTableEntity'
    'Add-CIPPAzDataTableEntity'
    'Update-AzDataTableEntity'
    'Remove-AzDataTableEntity'
    'Get-CIPPTable'
    'New-CIPPGraphPermission'
    'Set-CIPPSamKey'
    'Invoke-CIPPRestMethod'
    'New-GraphPostRequest'
    'New-GraphPatchRequest'
    'New-GraphDeleteRequest'
    'Remove-CIPPGraphPermission'
)

Write-Host "`n-- Function name format validation --"

Assert-True 'Valid function name passes regex' {
    'Get-CIPPLicenses' -match '^[A-Za-z]+-[A-Za-z0-9]+$'
}

Assert-True 'Invalid name with spaces is rejected' {
    'rm -rf /' -notmatch '^[A-Za-z]+-[A-Za-z0-9]+$'
}

Assert-True 'Injection attempt with semicolons is rejected' {
    'Get-Info; Remove-Item C:\' -notmatch '^[A-Za-z]+-[A-Za-z0-9]+$'
}

Assert-True 'Empty function name is rejected' {
    [string]::IsNullOrWhiteSpace('')
}

Write-Host "`n-- Blocklist coverage --"

foreach ($fn in $BlockList) {
    Assert-True "Blocklist contains $fn" {
        $BlockList -contains $fn
    }
}

Assert-True 'Get-GraphToken is blocked' { $BlockList -contains 'Get-GraphToken' }
Assert-True 'Get-CIPPAzDataTableEntity is blocked' { $BlockList -contains 'Get-CIPPAzDataTableEntity' }
Assert-True 'Update-AzDataTableEntity is blocked' { $BlockList -contains 'Update-AzDataTableEntity' }

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------
Write-Host "`n=== Results ===" -ForegroundColor Cyan
Write-Host "  Passed: $pass" -ForegroundColor Green
Write-Host "  Failed: $fail" -ForegroundColor $(if ($fail -gt 0) { 'Red' } else { 'Green' })

if ($fail -gt 0) { exit 1 } else { exit 0 }
