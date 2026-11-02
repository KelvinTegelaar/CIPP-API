# Pester tests for Get-CIPPSAMCertificateVersions (dev-mode current/previous)

BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
    $VersionsPath = Join-Path $RepoRoot 'Modules/CIPPCore/Public/Get-CIPPSAMCertificateVersions.ps1'
    $NewCertPath = Join-Path $RepoRoot 'Modules/CIPPCore/Public/New-CIPPSAMCertificate.ps1'

    function Get-CIPPTable { param($TableName) }
    function Get-CIPPAzDataTableEntity { param($Context, $Filter) }
    function Get-CippKeyVaultName { }
    function Get-CIPPAzIdentityToken { param($ResourceUrl) }
    function Invoke-CIPPRestMethod { }

    . $NewCertPath
    . $VersionsPath

    $script:CertA = New-CIPPSAMCertificate -SubjectName 'CN=CIPP-SAM-A'
    $script:CertB = New-CIPPSAMCertificate -SubjectName 'CN=CIPP-SAM-B'
}

Describe 'Get-CIPPSAMCertificateVersions dev-mode' {
    BeforeEach {
        $script:OriginalStorage = $env:AzureWebJobsStorage
        $script:OriginalNonLocal = $env:NonLocalHostAzurite
        $env:AzureWebJobsStorage = 'UseDevelopmentStorage=true'
        $env:NonLocalHostAzurite = $null
        Mock -CommandName Get-CIPPTable -MockWith { @{ Context = 'stub-table' } }
    }

    AfterEach {
        $env:AzureWebJobsStorage = $script:OriginalStorage
        $env:NonLocalHostAzurite = $script:OriginalNonLocal
    }

    It 'returns empty when DevSecrets has no SAMCertificate' {
        Mock -CommandName Get-CIPPAzDataTableEntity -MockWith { $null }

        $Result = Get-CIPPSAMCertificateVersions

        $Result.Current | Should -BeNullOrEmpty
        $Result.Previous | Should -BeNullOrEmpty
        $Result.HistoricalThumbprints.Count | Should -Be 0
    }

    It 'returns current and previous from DevSecrets properties' {
        Mock -CommandName Get-CIPPAzDataTableEntity -MockWith {
            [PSCustomObject]@{
                PartitionKey            = 'Secret'
                RowKey                  = 'Secret'
                SAMCertificate          = $script:CertA.PfxBase64
                SAMCertificatePrevious  = $script:CertB.PfxBase64
            }
        }

        $Result = Get-CIPPSAMCertificateVersions

        $Result.Current.Thumbprint | Should -Be $script:CertA.Thumbprint
        $Result.Previous.Thumbprint | Should -Be $script:CertB.Thumbprint
        $Result.AllKnownThumbprints | Should -Contain $script:CertA.Thumbprint
        $Result.AllKnownThumbprints | Should -Contain $script:CertB.Thumbprint
        $Result.HistoricalThumbprints.Count | Should -Be 0
    }
}
