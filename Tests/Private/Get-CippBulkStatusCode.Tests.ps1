BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
    . (Join-Path $RepoRoot 'Modules/CIPPCore/Public/Get-CippBulkStatusCode.ps1')
}

Describe 'Get-CippBulkStatusCode' {
    It 'returns <Expected> for <Failed> of <Total> failed' -ForEach @(
        @{ Total = 3; Failed = 0; Expected = 'OK' }
        @{ Total = 3; Failed = 1; Expected = 'MultiStatus' }
        @{ Total = 3; Failed = 3; Expected = 'InternalServerError' }
        @{ Total = 1; Failed = 1; Expected = 'InternalServerError' }
        @{ Total = 0; Failed = 0; Expected = 'OK' }
    ) {
        Get-CippBulkStatusCode -Total $Total -Failed $Failed | Should -Be ([System.Net.HttpStatusCode]::$Expected)
    }
}
