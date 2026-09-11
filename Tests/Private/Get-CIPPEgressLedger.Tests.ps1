# Pester tests for Get-CIPPEgressLedger
# The ledger is written by Craft outside this repo, so "no data yet" (missing file, stale
# day, garbage JSON) must be indistinguishable from a real zero-byte day: both return $null,
# never a fake 0 that looks like a reading.

BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
    . (Join-Path $RepoRoot 'Modules/CIPPCore/Public/Functions/Get-CIPPEgressLedger.ps1')
}

Describe 'Get-CIPPEgressLedger' {
    It 'returns the bytes when the ledger is for today' {
        $Now = [DateTime]::Parse('2026-09-11T12:00:00Z').ToUniversalTime()
        Set-Content -Path (Join-Path $TestDrive 'egress-ledger.json') -Value '{"DateUtc":"2026-09-11","Bytes":123456}'
        $Result = Get-CIPPEgressLedger -LogDirectory $TestDrive -Now $Now
        $Result.Bytes | Should -Be 123456
        $Result.DateUtc | Should -Be '2026-09-11'
    }

    It 'returns null when the ledger is for a previous UTC day' {
        $Now = [DateTime]::Parse('2026-09-11T12:00:00Z').ToUniversalTime()
        Set-Content -Path (Join-Path $TestDrive 'egress-ledger.json') -Value '{"DateUtc":"2026-09-10","Bytes":123456}'
        Get-CIPPEgressLedger -LogDirectory $TestDrive -Now $Now | Should -BeNullOrEmpty
    }

    It 'returns null when the file is missing' {
        Get-CIPPEgressLedger -LogDirectory (Join-Path $TestDrive 'does-not-exist') | Should -BeNullOrEmpty
    }

    It 'returns null for unparsable JSON' {
        Set-Content -Path (Join-Path $TestDrive 'egress-ledger.json') -Value 'not json {{'
        Get-CIPPEgressLedger -LogDirectory $TestDrive | Should -BeNullOrEmpty
    }
}
