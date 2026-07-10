function Get-CIPPSAMCertificate {
    <#
    .SYNOPSIS
    Retrieves the SAM certificate from Key Vault or the DevSecrets table

    .DESCRIPTION
    Loads the stored SAM certificate PFX and materializes it as an X509Certificate2 with
    its private key, for use with Get-GraphTokenFromCert. The read path is storage-mode
    agnostic: a Key Vault certificate's private key is exposed through the secrets endpoint
    under the same name, so a single secret GET covers both the certificate and the
    secret-fallback storage modes. Read-only - never creates or renews a certificate.

    .PARAMETER Name
    Storage name of the certificate. Defaults to SAMCertificate.

    .PARAMETER VaultName
    Name of the Key Vault. If not provided, derives via Get-CippKeyVaultName.

    .PARAMETER SkipCache
    Bypass the in-memory certificate cache and fetch from storage.

    .EXAMPLE
    $SAMCert = Get-CIPPSAMCertificate
    Get-GraphTokenFromCert -TenantId $env:TenantID -AppId $env:ApplicationID -Certificate $SAMCert.Certificate
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $false)]
        [string]$Name = 'SAMCertificate',

        [Parameter(Mandatory = $false)]
        [string]$VaultName,

        [switch]$SkipCache
    )

    # Serve from cache when fresh (1 hour TTL)
    if (-not $SkipCache -and $script:SAMCertificateCache.$Name -and $script:SAMCertificateCache.$Name.FetchedAt -gt (Get-Date).AddHours(-1)) {
        return $script:SAMCertificateCache.$Name.Result
    }

    if (-not $SkipCache -and $Name -eq 'SAMCertificate' -and $env:SAMCertificate) {
        # Preloaded by Get-CIPPAuthentication at startup (and refreshed by Set-CIPPSAMCertificate)
        $PfxBase64 = $env:SAMCertificate
    } elseif ($env:AzureWebJobsStorage -eq 'UseDevelopmentStorage=true' -or $env:NonLocalHostAzurite -eq 'true') {
        $Table = Get-CIPPTable -tablename 'DevSecrets'
        $Secret = Get-CIPPAzDataTableEntity @Table -Filter "PartitionKey eq 'Secret' and RowKey eq 'Secret'"
        $PfxBase64 = $Secret.$Name
    } else {
        try {
            $PfxBase64 = Get-CippKeyVaultSecret -VaultName $VaultName -Name $Name -AsPlainText -ErrorAction Stop
        } catch {
            # A missing secret means the certificate has not been created yet (bootstrap pending)
            if ($_.Exception.Message -match 'SecretNotFound|404') {
                return $null
            }
            throw
        }
    }

    if ([string]::IsNullOrEmpty($PfxBase64)) {
        return $null
    }

    $PfxBytes = [Convert]::FromBase64String($PfxBase64)
    try {
        # Ephemeral avoids writing key files to disk on the Linux consumption plan
        $Certificate = [System.Security.Cryptography.X509Certificates.X509Certificate2]::new(
            $PfxBytes,
            [string]::Empty,
            [System.Security.Cryptography.X509Certificates.X509KeyStorageFlags]::EphemeralKeySet
        )
    } catch {
        # EphemeralKeySet is not supported on all platforms (e.g. macOS local dev)
        $Certificate = [System.Security.Cryptography.X509Certificates.X509Certificate2]::new(
            $PfxBytes,
            [string]::Empty,
            [System.Security.Cryptography.X509Certificates.X509KeyStorageFlags]::Exportable
        )
    }

    $Result = [PSCustomObject]@{
        Certificate = $Certificate
        Thumbprint  = $Certificate.Thumbprint
        NotBefore   = $Certificate.NotBefore.ToUniversalTime()
        NotAfter    = $Certificate.NotAfter.ToUniversalTime()
    }

    if (-not $script:SAMCertificateCache) {
        $script:SAMCertificateCache = [HashTable]::Synchronized(@{})
    }
    $script:SAMCertificateCache.$Name = @{
        Result    = $Result
        FetchedAt = Get-Date
    }

    return $Result
}
