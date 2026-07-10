function Set-CIPPSAMCertificate {
    <#
    .SYNOPSIS
    Stores the SAM certificate PFX in Key Vault (dual-mode) or the DevSecrets table

    .DESCRIPTION
    Persists a base64 PFX. In production it first attempts the Key Vault certificates
    import API; if the managed identity lacks certificate permissions (403, the case on
    deployments created before certificate permissions were added to the templates) or the
    name is already occupied by a plain secret (409), it falls back to storing the base64
    PFX as a regular Key Vault secret. Both modes are readable through the secrets endpoint
    under the same name, so Get-CIPPSAMCertificate does not need to know which mode is active.
    In dev mode (Azurite) the PFX is stored on the DevSecrets table row instead.

    .PARAMETER PfxBase64
    The certificate as a base64-encoded passwordless PFX.

    .PARAMETER Name
    Storage name used for both the Key Vault certificate and the fallback secret. Defaults to SAMCertificate.

    .PARAMETER VaultName
    Name of the Key Vault. If not provided, derives via Get-CippKeyVaultName.

    .EXAMPLE
    Set-CIPPSAMCertificate -PfxBase64 $Cert.PfxBase64
    #>
    [System.Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingConvertToSecureStringWithPlainText', '')]
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$PfxBase64,

        [Parameter(Mandatory = $false)]
        [string]$Name = 'SAMCertificate',

        [Parameter(Mandatory = $false)]
        [string]$VaultName
    )

    if ($env:AzureWebJobsStorage -eq 'UseDevelopmentStorage=true' -or $env:NonLocalHostAzurite -eq 'true') {
        $Table = Get-CIPPTable -tablename 'DevSecrets'
        $Secret = Get-CIPPAzDataTableEntity @Table -Filter "PartitionKey eq 'Secret' and RowKey eq 'Secret'"
        if (!$Secret) {
            throw 'DevSecrets table row not found. Cannot store SAM certificate in dev mode.'
        }
        $Secret | Add-Member -MemberType NoteProperty -Name $Name -Value $PfxBase64 -Force
        Add-AzDataTableEntity @Table -Entity $Secret -Force
        Update-CIPPSAMCertificateEnvCache -Name $Name -PfxBase64 $PfxBase64
        return @{ StorageMode = 'DevTable'; Name = $Name }
    }

    if (-not $VaultName) {
        $VaultName = Get-CippKeyVaultName
        if (-not $VaultName) {
            throw 'VaultName not provided and could not be derived (WEBSITE_SITE_NAME / WEBSITE_DEPLOYMENT_ID not set)'
        }
    }

    $Token = Get-CIPPAzIdentityToken -ResourceUrl 'https://vault.azure.net'

    # Attempt the certificates import API first. exportable must be true so the private
    # key remains retrievable through the secrets endpoint.
    $ImportBody = @{
        value  = $PfxBase64
        policy = @{
            key_props    = @{
                exportable = $true
                kty        = 'RSA'
                key_size   = 2048
                reuse_key  = $false
            }
            secret_props = @{
                contentType = 'application/x-pkcs12'
            }
        }
    } | ConvertTo-Json -Compress -Depth 10

    $ImportUri = "https://$VaultName.vault.azure.net/certificates/$Name/import?api-version=7.4"
    $StatusCode = $null
    $ImportResponse = Invoke-CIPPRestMethod -Uri $ImportUri -Method POST -Body $ImportBody -ContentType 'application/json' -Headers @{
        Authorization = "Bearer $Token"
    } -SkipHttpErrorCheck -StatusCodeVariable StatusCode

    if ($StatusCode -ge 200 -and $StatusCode -lt 300) {
        Write-LogMessage -API 'SAMCertificate' -message "Stored SAM certificate '$Name' as a Key Vault certificate in vault '$VaultName'" -sev 'Info'
        Update-CIPPSAMCertificateEnvCache -Name $Name -PfxBase64 $PfxBase64
        return @{ StorageMode = 'Certificate'; Name = $Name; VaultName = $VaultName }
    }

    if ($StatusCode -eq 403 -or $StatusCode -eq 409) {
        # 403: access policy has no certificate permissions (pre-existing deployments).
        # 409: the name is already owned by a plain secret from prior secret-mode operation.
        # Either way, fall back to storing the base64 PFX as a regular secret.
        Write-Information "Key Vault certificate import returned $StatusCode, falling back to secret storage for '$Name'"
        try {
            $null = Set-CippKeyVaultSecret -VaultName $VaultName -Name $Name -SecretValue (ConvertTo-SecureString -String $PfxBase64 -AsPlainText -Force)
        } catch {
            # A 409 on the secret PUT means the name is backed by a Key Vault certificate but we can
            # no longer import one - certificate permissions were revoked after operating in
            # certificate mode. Manual intervention required; the previous certificate remains valid.
            Write-LogMessage -API 'SAMCertificate' -message "Failed to store SAM certificate '$Name' in vault '$VaultName'. If certificate permissions were removed from the Key Vault access policy after the certificate was stored via the certificates API, restore them (get, list, import, update, delete). See Log Data for details." -sev 'CRITICAL' -LogData (Get-CippException -Exception $_)
            throw
        }
        Update-CIPPSAMCertificateEnvCache -Name $Name -PfxBase64 $PfxBase64
        return @{ StorageMode = 'Secret'; Name = $Name; VaultName = $VaultName }
    }

    $ErrorDetail = if ($ImportResponse.error.message) { $ImportResponse.error.message } else { $ImportResponse | ConvertTo-Json -Compress -Depth 5 }
    throw "Key Vault certificate import for '$Name' in vault '$VaultName' failed with status $StatusCode : $ErrorDetail"
}
