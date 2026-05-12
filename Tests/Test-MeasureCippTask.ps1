#!/usr/bin/env pwsh
[CmdletBinding()]
param()

$RepoRoot = Split-Path -Parent $PSScriptRoot
$FunctionPath = Join-Path $RepoRoot 'Modules/CIPPCore/Public/Tools/Measure-CippTask.ps1'

if (-not (Test-Path $FunctionPath)) {
    Write-Error "Measure-CippTask.ps1 not found at: $FunctionPath"
    exit 1
}

. $FunctionPath

function New-TestTelemetryClient {
    $Client = [pscustomobject]@{
        Events     = [System.Collections.Generic.List[object]]::new()
        FlushCount  = 0
    }

    $Client | Add-Member -MemberType ScriptMethod -Name TrackEvent -Value {
        param($EventName, $Props, $Metrics)
        $this.Events.Add([pscustomobject]@{
                EventName = $EventName
                Props     = $Props
                Metrics   = $Metrics
            })
    } -Force

    $Client | Add-Member -MemberType ScriptMethod -Name Flush -Value {
        $this.FlushCount++
    } -Force

    return $Client
}

function Assert-Equal {
    param(
        [string]$Label,
        $Actual,
        $Expected
    )

    if ($Actual -ne $Expected) {
        Write-Host "[FAIL] $Label" -ForegroundColor Red
        Write-Host "       Expected: $Expected"
        Write-Host "       Actual:   $Actual"
        return $false
    }

    Write-Host "[PASS] $Label" -ForegroundColor Green
    return $true
}

$Failures = 0

$global:TelemetryClient = New-TestTelemetryClient
$SuccessResult = Measure-CippTask -TaskName 'SuccessTask' -Metadata @{
    InvocationId = 'inv-success'
    Endpoint     = 'CIPPHttpTrigger'
} -Script {
    'ok'
}

if (-not (Assert-Equal -Label 'returns the script result' -Actual $SuccessResult -Expected 'ok')) { $Failures++ }
if (-not (Assert-Equal -Label 'records one telemetry event' -Actual $global:TelemetryClient.Events.Count -Expected 1)) { $Failures++ }
if (-not (Assert-Equal -Label 'does not flush on success' -Actual $global:TelemetryClient.FlushCount -Expected 0)) { $Failures++ }
if (-not (Assert-Equal -Label 'marks success outcome' -Actual $global:TelemetryClient.Events[0].Props['Outcome'] -Expected 'Succeeded')) { $Failures++ }
if (-not (Assert-Equal -Label 'preserves invocation id' -Actual $global:TelemetryClient.Events[0].Props['InvocationId'] -Expected 'inv-success')) { $Failures++ }

$global:TelemetryClient = New-TestTelemetryClient
$CancellationThrew = $false
try {
    Measure-CippTask -TaskName 'CancelTask' -Metadata @{
        InvocationId = 'inv-cancel'
    } -Script {
        throw [System.Threading.Tasks.TaskCanceledException]::new('cancelled')
    } | Out-Null
} catch {
    $CancellationThrew = $true
}

if (-not (Assert-Equal -Label 'rethrows task cancellations' -Actual $CancellationThrew -Expected $true)) { $Failures++ }
if (-not (Assert-Equal -Label 'flushes on cancellation' -Actual $global:TelemetryClient.FlushCount -Expected 1)) { $Failures++ }
if (-not (Assert-Equal -Label 'marks cancellation outcome' -Actual $global:TelemetryClient.Events[0].Props['Outcome'] -Expected 'Cancelled')) { $Failures++ }
if (-not (Assert-Equal -Label 'captures cancellation error type' -Actual $global:TelemetryClient.Events[0].Props['ErrorType'] -Expected 'TaskCanceledException')) { $Failures++ }

if ($Failures -gt 0) {
    Write-Host "[FAIL] Measure-CippTask validation failed with $Failures issue(s)." -ForegroundColor Red
    exit 1
}

Write-Host "[PASS] Measure-CippTask validation passed." -ForegroundColor Green
