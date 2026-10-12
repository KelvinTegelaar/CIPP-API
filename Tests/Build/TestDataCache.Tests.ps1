BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
    Add-Type -Path (Join-Path $RepoRoot 'Shared/CIPPSharp/bin/CIPPSharp.dll')
    . (Join-Path $RepoRoot 'Modules/CIPPCore/Public/Get-CIPPTestData.ps1')
    function Get-CippTestDataFieldManifest { @('id', 'displayName') }
    function New-CIPPDbRequest { $script:Loads++; , @([pscustomobject]@{ id = 'parsed' }) }
}

Describe 'TestDataCache' {
    BeforeEach {
        [CIPP.TestDataCache]::Clear()
        [CIPP.TestDataCache]::Configure(300MB, 300)
        $script:Loads = 0
    }
    AfterAll { [CIPP.TestDataCache]::Clear(); [CIPP.TestDataCache]::Configure(300MB, 300) }

    It 'serves a projected request from whole records already cached, without loading or counting a miss' {
        $Whole = @([pscustomobject]@{ id = 'whole'; displayName = 'x'; extra = 1 })
        [CIPP.TestDataCache]::Set('contoso.com|Users', $Whole)

        $Result = Get-CIPPTestData -TenantFilter 'contoso.com' -Type 'Users'

        $Result[0].id | Should -Be 'whole'
        $script:Loads | Should -Be 0
        [CIPP.TestDataCache]::Misses | Should -Be 1
    }

    It 'loads and caches the projection when no whole records are cached' {
        (Get-CIPPTestData -TenantFilter 'contoso.com' -Type 'Users')[0].id | Should -Be 'parsed'
        (Get-CIPPTestData -TenantFilter 'contoso.com' -Type 'Users')[0].id | Should -Be 'parsed'
        $script:Loads | Should -Be 1
    }

    It 'sweeps expired entries' {
        [CIPP.TestDataCache]::Configure(300MB, 1)
        [CIPP.TestDataCache]::Set('contoso.com|Users', @([pscustomobject]@{ id = 1 }))
        Start-Sleep -Milliseconds 1100
        [CIPP.TestDataCache]::ClearExpired() | Should -Be 1
        [CIPP.TestDataCache]::Count | Should -Be 0
    }

    It 'estimates a row from its fields' {
        $Row = [pscustomobject]@{ id = 'a'; when = [datetime]::UtcNow; tags = @('x', 'y') }
        [CIPP.TestDataCache]::Set('k', @($Row))
        $Bytes = [CIPP.TestDataCache]::CurrentBytes
        $Bytes | Should -BeGreaterThan 0
        $Bytes | Should -BeLessThan 2KB
    }
}
