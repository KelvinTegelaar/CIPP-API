# Pester tests for Set-CIPPSAMCertificate
# Dev-mode storage writes the PFX into the DevSecrets Secret row. A certificate-only First Setup
# registers the certificate before that row exists, so the function must create it rather than throw.

BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
    $FunctionPath = Join-Path $RepoRoot 'Modules/CIPPCore/Public/Set-CIPPSAMCertificate.ps1'

    # Minimal stubs so Mock has commands to replace during tests
    function Get-CIPPTable { param($TableName) }
    function Get-CIPPAzDataTableEntity { param($Context, $Filter) }
    function Add-AzDataTableEntity { param($Context, $Entity, [switch]$Force) }
    function Update-CIPPSAMCertificateEnvCache { param($Name, $PfxBase64) }
    function Get-CippKeyVaultName { }

    . $FunctionPath
}

Describe 'Set-CIPPSAMCertificate dev-mode storage' {
    BeforeEach {
        $script:OriginalStorage = $env:AzureWebJobsStorage
        $script:OriginalNonLocal = $env:NonLocalHostAzurite
        $env:AzureWebJobsStorage = 'UseDevelopmentStorage=true'
        $env:NonLocalHostAzurite = $null

        $script:Written = $null
        Mock -CommandName Get-CIPPTable -MockWith { @{ Context = 'stub-table' } }
        Mock -CommandName Add-AzDataTableEntity -MockWith { $script:Written = $Entity }
        Mock -CommandName Update-CIPPSAMCertificateEnvCache -MockWith { }
    }

    AfterEach {
        $env:AzureWebJobsStorage = $script:OriginalStorage
        $env:NonLocalHostAzurite = $script:OriginalNonLocal
    }

    It 'creates the Secret row when DevSecrets is empty (fresh certificate-only setup)' {
        Mock -CommandName Get-CIPPAzDataTableEntity -MockWith { $null }

        $Result = Set-CIPPSAMCertificate -PfxBase64 'cGZ4'

        $Result.StorageMode | Should -Be 'DevTable'
        Should -Invoke -CommandName Add-AzDataTableEntity -Times 1 -Exactly
        $script:Written.PartitionKey | Should -Be 'Secret'
        $script:Written.RowKey | Should -Be 'Secret'
        $script:Written.SAMCertificate | Should -Be 'cGZ4'
    }

    It 'updates the existing Secret row without touching its other properties' {
        Mock -CommandName Get-CIPPAzDataTableEntity -MockWith {
            [PSCustomObject]@{ PartitionKey = 'Secret'; RowKey = 'Secret'; tenantid = 'tenant-a'; applicationid = 'app-a' }
        }

        $null = Set-CIPPSAMCertificate -PfxBase64 'bmV3'

        $script:Written.tenantid | Should -Be 'tenant-a'
        $script:Written.applicationid | Should -Be 'app-a'
        $script:Written.SAMCertificate | Should -Be 'bmV3'
    }
}
