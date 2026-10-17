function Test-CIPPSAMCertificateAuth {
    <#
    .SYNOPSIS
    Proves the stored SAM certificate can obtain a token for the SAM app

    .DESCRIPTION
    Reads the stored certificate (bypassing caches) and requests an uncached app-only token with it.
    On success, refreshes the in-process certificate caches so this process signs with the verified cert.

    .FUNCTIONALITY
    Internal
    #>
    [CmdletBinding()]
    param(
        [string]$ApplicationId = $env:ApplicationID,
        [string]$TenantId = $env:TenantID
    )

    $Cert = Get-CIPPSAMCertificate -SkipCache
    if (-not $Cert) {
        return [PSCustomObject]@{ Success = $false; Thumbprint = $null; Error = 'No SAM certificate is stored.' }
    }

    try {
        $Token = Get-GraphTokenFromCert -TenantId $TenantId -AppId $ApplicationId -Certificate $Cert.Certificate -SkipCache -ErrorAction Stop
        if (-not $Token.access_token) { throw 'The token response did not contain an access token.' }
    } catch {
        $ErrorMessage = if ($_.ErrorDetails.Message) { Get-NormalizedError -message $_.ErrorDetails.Message } else { $_.Exception.Message }
        return [PSCustomObject]@{ Success = $false; Thumbprint = $Cert.Thumbprint; Error = $ErrorMessage }
    }

    if ($Cert.PfxBase64) {
        Update-CIPPSAMCertificateEnvCache -Name 'SAMCertificate' -PfxBase64 $Cert.PfxBase64
    }
    return [PSCustomObject]@{ Success = $true; Thumbprint = $Cert.Thumbprint; Error = $null }
}
