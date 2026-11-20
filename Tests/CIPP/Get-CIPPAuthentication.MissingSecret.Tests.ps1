# A certificate-auth install can have no ApplicationSecret in Key Vault. That alone must not stop the
# other credentials loading, or every worker loses TenantID/RefreshToken and the UI falls back to setup.

BeforeAll {
    $BackendRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))

    function Get-CippKeyVaultName { 'testvault' }
    function Get-CippKeyVaultSecret { param($VaultName, $Name, [switch]$AsPlainText) }
    function Get-CIPPFeatureFlag { param($Id) @{ Enabled = $true } }
    function Update-CIPPSAMCertificate {}
    function Write-LogMessage { param($message, $Sev, $API, $LogData) }
    function Get-CippException { param($Exception) $Exception }

    . (Join-Path $BackendRoot 'Modules/CIPPCore/Public/Get-CIPPAuthentication.ps1')

    $script:EnvNames = @('AzureWebJobsStorage', 'NonLocalHostAzurite', 'ApplicationID', 'ApplicationSecret', 'TenantID', 'RefreshToken', 'SAMCertificate', 'SetFromProfile', 'CertificateAuthMode')
}

Describe 'Get-CIPPAuthentication with a missing Key Vault secret' {
    BeforeEach {
        $script:SavedEnv = @{}
        foreach ($Name in $script:EnvNames) {
            $script:SavedEnv[$Name] = [Environment]::GetEnvironmentVariable($Name)
            [Environment]::SetEnvironmentVariable($Name, $null)
        }
        $env:AzureWebJobsStorage = 'DefaultEndpointsProtocol=https;AccountName=test'
        $env:ApplicationSecret = 'stale-secret'

        $script:Vault = @{
            ApplicationID  = '11111111-1111-1111-1111-111111111111'
            TenantID       = '22222222-2222-2222-2222-222222222222'
            RefreshToken   = 'refresh-token'
            SAMCertificate = 'pfx'
        }
        Mock Get-CippKeyVaultSecret {
            if ($script:Vault.ContainsKey($Name)) { return $script:Vault[$Name] }
            throw "Key Vault secret retrieval failed: Failed to retrieve secret '$Name' from vault '$VaultName': Response status code does not indicate success: 404 (Not Found)."
        }
        Mock Write-LogMessage {}
        Mock Get-CIPPFeatureFlag { @{ Enabled = $true } }
    }

    AfterEach {
        foreach ($Name in $script:EnvNames) {
            [Environment]::SetEnvironmentVariable($Name, $script:SavedEnv[$Name])
        }
    }

    It 'loads the other credentials when ApplicationSecret does not exist' {
        Get-CIPPAuthentication | Should -BeTrue

        $env:ApplicationID | Should -Be '11111111-1111-1111-1111-111111111111'
        $env:TenantID | Should -Be '22222222-2222-2222-2222-222222222222'
        $env:RefreshToken | Should -Be 'refresh-token'
        $env:ApplicationSecret | Should -BeNullOrEmpty
        Should -Invoke Write-LogMessage -Times 0 -ParameterFilter { $Sev -eq 'CRITICAL' }
    }

    It 'still fails on a missing ApplicationSecret when certificate auth is off' {
        Mock Get-CIPPFeatureFlag { @{ Enabled = $false } }

        Get-CIPPAuthentication | Should -BeFalse
        Should -Invoke Write-LogMessage -Times 1 -ParameterFilter { $Sev -eq 'CRITICAL' }
    }

    It 'still fails when a required credential does not exist' {
        $script:Vault.Remove('TenantID')

        Get-CIPPAuthentication | Should -BeFalse
        Should -Invoke Write-LogMessage -Times 1 -ParameterFilter { $Sev -eq 'CRITICAL' }
    }

    It 'still fails when ApplicationSecret cannot be read for another reason' {
        Mock Get-CippKeyVaultSecret {
            if ($Name -eq 'ApplicationSecret') { throw 'Key Vault secret retrieval failed: 403 (Forbidden)' }
            $script:Vault[$Name]
        }

        Get-CIPPAuthentication | Should -BeFalse
        Should -Invoke Write-LogMessage -Times 1 -ParameterFilter { $Sev -eq 'CRITICAL' }
    }
}
