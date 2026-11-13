BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
    Add-Type -Path (Join-Path $RepoRoot 'Shared/CIPPSharp/bin/CIPPSharp.dll')
    function Get-TokenCacheDiagnostics { [CIPP.CIPPTokenCache]::GetDiagnostics() | ConvertFrom-Json }
}

Describe 'CIPPTokenCache bounds' {
    BeforeEach { $null = [CIPP.CIPPTokenCache]::Clear(); [CIPP.CIPPTokenCache]::ResetDiagnostics() }

    It 'drops expired entries that are never looked up again' {
        $Expired = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds() - 10
        foreach ($i in 1..2000) { [CIPP.CIPPTokenCache]::Store("tenant$i|scope|app||client_credentials|failed", 'AADSTS53003', $Expired) }
        (Get-TokenCacheDiagnostics).Entries | Should -BeLessOrEqual 256
    }

    It 'never holds more than 10000 entries' {
        $Live = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds() + 3600
        foreach ($i in 1..12000) { [CIPP.CIPPTokenCache]::Store("tenant$i|scope|app||client_credentials", '{}', $Live + $i) }
        (Get-TokenCacheDiagnostics).Entries | Should -BeLessOrEqual 10000
        [CIPP.CIPPTokenCache]::Lookup('tenant12000|scope|app||client_credentials', 120).Found | Should -BeTrue
    }

    It 'keeps live entries when sweeping expired ones' {
        $Now = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds()
        [CIPP.CIPPTokenCache]::Store('live|scope|app||client_credentials', '{"access_token":"x"}', $Now + 3600)
        foreach ($i in 1..600) { [CIPP.CIPPTokenCache]::Store("dead$i", 'x', $Now - 10) }
        [CIPP.CIPPTokenCache]::Lookup('live|scope|app||client_credentials', 120).TokenPayloadJson | Should -Be '{"access_token":"x"}'
    }

    It 'drops the per-key lock of a key with no cached entry once it is released' {
        foreach ($i in 1..1000) {
            $null = [CIPP.CIPPTokenCache]::AcquireLock("lock$i", 0)
            [CIPP.CIPPTokenCache]::ReleaseLock("lock$i")
        }
        $Expired = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds() - 10
        foreach ($i in 1..256) { [CIPP.CIPPTokenCache]::Store("sweep$i", 'x', $Expired) }
        (Get-TokenCacheDiagnostics).ActiveLocks | Should -BeLessOrEqual 1
    }

    It 'keeps a lock that is held through a sweep' {
        [CIPP.CIPPTokenCache]::AcquireLock('held', 0) | Should -BeTrue
        $Expired = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds() - 10
        foreach ($i in 1..256) { [CIPP.CIPPTokenCache]::Store("sweep$i", 'x', $Expired) }
        [CIPP.CIPPTokenCache]::AcquireLock('held', 0) | Should -BeFalse
        [CIPP.CIPPTokenCache]::ReleaseLock('held')
        [CIPP.CIPPTokenCache]::AcquireLock('held', 0) | Should -BeTrue
        [CIPP.CIPPTokenCache]::ReleaseLock('held')
    }
}
