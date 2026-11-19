BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))

    function Get-CippTable { param($tablename) @{} }
    function Get-CIPPAzDataTableEntity { param($Filter, $Property) }
    function Add-CIPPAzDataTableEntity { param($Entity, [switch]$Force) }
    function Write-LogMessage { }

    . (Join-Path $RepoRoot 'Modules/CIPPCore/Public/Authentication/Get-CippAccessScopeVersion.ps1')
    . (Join-Path $RepoRoot 'Modules/CIPPCore/Public/Authentication/Clear-CippAccessScopeCache.ps1')
}

Describe 'Access scope version stamp' {
    BeforeEach {
        $script:CippAccessScopeVersionMemo = $null
        $script:Stamp = $null
        Mock Get-CIPPAzDataTableEntity { if ($script:Stamp) { [PSCustomObject]@{ Version = $script:Stamp } } }
        Mock Add-CIPPAzDataTableEntity { $script:Stamp = $Entity.Version }
    }

    It 'reads the stamp once and then answers from its memo' {
        $script:Stamp = 'v1'
        Get-CippAccessScopeVersion | Should -Be 'v1'
        Get-CippAccessScopeVersion | Should -Be 'v1'
        Should -Invoke Get-CIPPAzDataTableEntity -Times 1 -Exactly
    }

    It 'reads the stamp again once its memo lapses' {
        $script:Stamp = 'v1'
        $null = Get-CippAccessScopeVersion
        $script:Stamp = 'v2'
        $script:CippAccessScopeVersionMemo.Expires = [datetime]::UtcNow.AddSeconds(-1)
        Get-CippAccessScopeVersion | Should -Be 'v2'
    }

    It 'writes a new stamp when there is none, so a version value is never reused' {
        $First = Get-CippAccessScopeVersion
        [guid]::TryParse($First, [ref][guid]::Empty) | Should -BeTrue
        $script:Stamp | Should -Be $First

        # The stamp table is deleted by a cache clear: the next read must not land on an earlier value
        $script:Stamp = $null
        $script:CippAccessScopeVersionMemo = $null
        $Second = Get-CippAccessScopeVersion
        $Second | Should -Not -Be $First
        $script:Stamp | Should -Be $Second
    }

    It 'returns a fresh value each time the stamp cannot be read, and keeps none of them' {
        Mock Get-CIPPAzDataTableEntity { throw 'storage down' }
        $First = Get-CippAccessScopeVersion 3>$null
        $Second = Get-CippAccessScopeVersion 3>$null
        $Second | Should -Not -Be $First
        $script:CippAccessScopeVersionMemo | Should -BeNullOrEmpty
    }

    It 'a clear writes a new stamp and drops this worker''s caches, even when the stamp cannot be written' {
        $script:Stamp = 'v1'
        $null = Get-CippAccessScopeVersion
        $script:CippRoleIPRangeCache = @{ x = 1 }
        $script:CippRolePermissionCache = @{ x = 1 }

        Clear-CippAccessScopeCache -Confirm:$false
        $script:Stamp | Should -Not -Be 'v1'
        $script:CippRoleIPRangeCache | Should -BeNullOrEmpty
        $script:CippRolePermissionCache | Should -BeNullOrEmpty
        Get-CippAccessScopeVersion | Should -Be $script:Stamp

        $script:CippRolePermissionCache = @{ x = 1 }
        Mock Add-CIPPAzDataTableEntity { throw 'storage down' }
        Clear-CippAccessScopeCache -Confirm:$false
        $script:CippRolePermissionCache | Should -BeNullOrEmpty
        $script:CippAccessScopeVersionMemo | Should -BeNullOrEmpty
    }
}
