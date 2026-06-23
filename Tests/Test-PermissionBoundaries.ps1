#!/usr/bin/env pwsh
<#
.SYNOPSIS
    Tests that CIPP role permission boundaries are correctly enforced.
.DESCRIPTION
    Validates the ConvertTo-CIPPODataFilterValue sanitizer is in use at all known
    injection points and that role logic behaves as expected for key scenarios.
.NOTES
    Does not require a live API — tests source patterns and filter logic in isolation.
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

# ---------------------------------------------------------------------------
# Load sanitizer
# ---------------------------------------------------------------------------
$helperPath = Join-Path $PSScriptRoot '../Modules/CIPPCore/Public/ConvertTo-CIPPODataFilterValue.ps1'
if (-not (Test-Path $helperPath)) {
    Write-Error "ConvertTo-CIPPODataFilterValue.ps1 not found at: $helperPath"
    exit 1
}
. $helperPath

# ---------------------------------------------------------------------------
# Verify injection points in source files use the sanitizer
# ---------------------------------------------------------------------------
Write-Host "`n=== OData Sanitizer Usage Audit ===" -ForegroundColor Cyan

$ApiRoot = Join-Path $PSScriptRoot '../Modules/CIPPHTTP/Public/Entrypoints/HTTP Functions/CIPP'

function Assert-FileUsesSanitizer {
    param([string]$Label, [string]$FilePath)
    if (-not (Test-Path $FilePath)) {
        Write-Host "  [SKIP] $Label — file not found: $FilePath" -ForegroundColor DarkYellow
        return
    }
    $content = Get-Content $FilePath -Raw
    if ($content -match 'ConvertTo-CIPPODataFilterValue') {
        Write-Host "  [PASS] $Label" -ForegroundColor Green
        $script:pass++
    } else {
        Write-Host "  [FAIL] $Label — no ConvertTo-CIPPODataFilterValue found" -ForegroundColor Red
        $script:fail++
    }
}

Assert-FileUsesSanitizer `
    'Invoke-ExecDurableFunctions uses sanitizer' `
    (Join-Path $ApiRoot 'Core/Invoke-ExecDurableFunctions.ps1')

Assert-FileUsesSanitizer `
    'Invoke-AddScheduledItem uses sanitizer' `
    (Join-Path $ApiRoot 'Scheduler/Invoke-AddScheduledItem.ps1')

Assert-FileUsesSanitizer `
    'Invoke-ExecCustomRole uses sanitizer' `
    (Join-Path $ApiRoot 'Settings/Invoke-ExecCustomRole.ps1')

# ---------------------------------------------------------------------------
# Verify ExecCippFunction blocklist and name validation
# ---------------------------------------------------------------------------
Write-Host "`n=== ExecCippFunction Source Audit ===" -ForegroundColor Cyan

$ExecFunctionPath = Join-Path $ApiRoot 'Core/Invoke-ExecCippFunction.ps1'

Assert-True 'ExecCippFunction has expanded blocklist (Get-CIPPAzDataTableEntity)' {
    $content = Get-Content $ExecFunctionPath -Raw
    $content -match 'Get-CIPPAzDataTableEntity'
}

Assert-True 'ExecCippFunction validates function name format with regex' {
    $content = Get-Content $ExecFunctionPath -Raw
    $content -match 'notmatch.*\^.*\[A-Za-z\]'
}

Assert-True 'ExecCippFunction logs all calls with Write-LogMessage' {
    $content = Get-Content $ExecFunctionPath -Raw
    $content -match 'Write-LogMessage'
}

Assert-True 'ExecCippFunction returns generic error (not raw exception)' {
    $content = Get-Content $ExecFunctionPath -Raw
    $content -match 'An error occurred'
}

# ---------------------------------------------------------------------------
# Verify auth hardening in Test-CIPPAccess
# ---------------------------------------------------------------------------
Write-Host "`n=== Test-CIPPAccess Source Audit ===" -ForegroundColor Cyan

$AuthPath = Join-Path $PSScriptRoot '../Modules/CIPPCore/Public/Authentication/Test-CIPPAccess.ps1'

Assert-True 'Test-CIPPAccess wraps base64 decode in try-catch' {
    $content = Get-Content $AuthPath -Raw
    $content -match 'try\s*\{[^}]*FromBase64String'
}

Assert-True 'Test-CIPPAccess checks for empty/null header before decode' {
    $content = Get-Content $AuthPath -Raw
    $content -match 'IsNullOrWhiteSpace\s*\(\s*\$RawPrincipal\s*\)'
}

Assert-True 'Test-CIPPAccess logs malformed principal errors' {
    $content = Get-Content $AuthPath -Raw
    $content -match 'Write-LogMessage.*malformed'
}

# ---------------------------------------------------------------------------
# Sanitizer correctness: key injection scenarios
# ---------------------------------------------------------------------------
Write-Host "`n=== Sanitizer Correctness for Permission-Critical Filters ===" -ForegroundColor Cyan

Assert-True 'Role name with injection payload is escaped' {
    $safe = ConvertTo-CIPPODataFilterValue -Value "admin' or RowKey ne '" -Type String
    $filter = "RowKey eq '$safe'"
    # The filter must not contain unescaped injection operator
    $filter -notmatch "RowKey ne '"
}

Assert-True 'Safe role name passes through unchanged' {
    $safe = ConvertTo-CIPPODataFilterValue -Value 'myrole' -Type String
    $safe -eq 'myrole'
}

Assert-True 'PartitionKey injection payload is neutralised' {
    $safe = ConvertTo-CIPPODataFilterValue -Value "' or PartitionKey ne '" -Type String
    $filter = "PartitionKey eq '$safe'"
    # Verify the escaped value cannot break out of the quoted string
    $safe -eq "'' or PartitionKey ne ''"
}

Assert-Throws 'Invalid GUID role name throws instead of filtering all rows' {
    ConvertTo-CIPPODataFilterValue -Value "' or 1 eq 1" -Type Guid
}

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------
Write-Host "`n=== Results ===" -ForegroundColor Cyan
Write-Host "  Passed: $pass" -ForegroundColor Green
Write-Host "  Failed: $fail" -ForegroundColor $(if ($fail -gt 0) { 'Red' } else { 'Green' })

if ($fail -gt 0) { exit 1 } else { exit 0 }
