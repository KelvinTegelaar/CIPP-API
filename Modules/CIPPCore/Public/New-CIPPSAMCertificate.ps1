function New-CIPPSAMCertificate {
    <#
    .SYNOPSIS
    Generates a self-signed certificate for SAM app certificate-based authentication

    .DESCRIPTION
    Creates a new RSA self-signed certificate in memory suitable for use as a key credential
    on the SAM app registration (consumed by Get-GraphTokenFromCert). Pure generation - no
    storage or Graph interaction. The PFX is exported without a password so it is
    byte-compatible with how Key Vault exposes certificate private keys through the secrets
    endpoint (application/x-pkcs12); protection comes from Key Vault access control.

    .PARAMETER ValidityDays
    Number of days the certificate is valid for. Defaults to 365.

    .PARAMETER KeySize
    RSA key size in bits. Defaults to 2048.

    .PARAMETER SubjectName
    Certificate subject. Defaults to CN=CIPP-SAM-<site name>.

    .EXAMPLE
    New-CIPPSAMCertificate

    .EXAMPLE
    New-CIPPSAMCertificate -ValidityDays 730 -KeySize 4096
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $false)]
        [int]$ValidityDays = 365,

        [Parameter(Mandatory = $false)]
        [int]$KeySize = 2048,

        [Parameter(Mandatory = $false)]
        [string]$SubjectName
    )

    if ([string]::IsNullOrEmpty($SubjectName)) {
        # Machine name for local dev (WEBSITE_SITE_NAME is often set there too), site name in Azure
        if ($env:AzureWebJobsStorage -eq 'UseDevelopmentStorage=true' -or $env:NonLocalHostAzurite -eq 'true') {
            $InstanceName = [System.Environment]::MachineName
        } else {
            $InstanceName = $env:WEBSITE_SITE_NAME
        }
        $SubjectName = "CN=CIPP-SAM-$InstanceName"
    }

    $RSA = [System.Security.Cryptography.RSA]::Create($KeySize)
    try {
        $CertRequest = [System.Security.Cryptography.X509Certificates.CertificateRequest]::new(
            $SubjectName,
            $RSA,
            [System.Security.Cryptography.HashAlgorithmName]::SHA256,
            [System.Security.Cryptography.RSASignaturePadding]::Pkcs1
        )

        # Key usage: digital signature only (client assertion signing)
        $CertRequest.CertificateExtensions.Add(
            [System.Security.Cryptography.X509Certificates.X509KeyUsageExtension]::new(
                [System.Security.Cryptography.X509Certificates.X509KeyUsageFlags]::DigitalSignature,
                $true
            )
        )

        # Enhanced key usage: client authentication
        $EkuOids = [System.Security.Cryptography.OidCollection]::new()
        $null = $EkuOids.Add([System.Security.Cryptography.Oid]::new('1.3.6.1.5.5.7.3.2'))
        $CertRequest.CertificateExtensions.Add(
            [System.Security.Cryptography.X509Certificates.X509EnhancedKeyUsageExtension]::new($EkuOids, $false)
        )

        # Subject key identifier
        $CertRequest.CertificateExtensions.Add(
            [System.Security.Cryptography.X509Certificates.X509SubjectKeyIdentifierExtension]::new($CertRequest.PublicKey, $false)
        )

        # Backdate NotBefore to tolerate clock skew between this host and Entra ID
        $NotBefore = (Get-Date).ToUniversalTime().AddMinutes(-15)
        $NotAfter = $NotBefore.AddDays($ValidityDays)

        $Certificate = $CertRequest.CreateSelfSigned($NotBefore, $NotAfter)
        try {
            $PfxBytes = $Certificate.Export([System.Security.Cryptography.X509Certificates.X509ContentType]::Pfx)
            $PublicKeyBytes = $Certificate.Export([System.Security.Cryptography.X509Certificates.X509ContentType]::Cert)

            return [PSCustomObject]@{
                Certificate     = $Certificate
                PfxBase64       = [Convert]::ToBase64String($PfxBytes)
                PublicKeyBase64 = [Convert]::ToBase64String($PublicKeyBytes)
                Thumbprint      = $Certificate.Thumbprint
                NotBefore       = $NotBefore
                NotAfter        = $NotAfter
            }
        } catch {
            $Certificate.Dispose()
            throw
        }
    } finally {
        $RSA.Dispose()
    }
}
