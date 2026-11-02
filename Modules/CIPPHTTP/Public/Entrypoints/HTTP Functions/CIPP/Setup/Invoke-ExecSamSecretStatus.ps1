function Invoke-ExecSamSecretStatus {
    <#
    .FUNCTIONALITY
        Entrypoint,AnyTenant
    .ROLE
        CIPP.AppSettings.ReadWrite
    .SYNOPSIS
        Reports whether the stored SAM application secret is usable yet.
    .DESCRIPTION
        The setup wizard creates a client secret on one step and uses it on the next, but Entra
        can take several minutes to replicate a newly created secret. Until it has, every token
        request fails with AADSTS7000215 even though the value CIPP holds is correct. This lets
        the wizard wait on that instead of failing the user after they have already signed in.
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    try {
        $null = Get-CIPPAuthentication

        # Certificate mode has no client secret to wait on - report ready once the SAM certificate
        # exists, so the sign-in step isn't gated on a secret that will never be created.
        if ($env:CertificateAuthMode) {
            $Cert = Get-CIPPSAMCertificate -SkipCache -ErrorAction SilentlyContinue
            if ($Cert) {
                $Results = @{ ready = $true; reason = 'certificate' }
            } else {
                $Results = @{
                    ready   = $false
                    reason  = 'certificatePending'
                    message = 'Preparing the SAM certificate. This unlocks automatically once the certificate is registered on the application.'
                }
            }
            return ([HttpResponseContext]@{
                    StatusCode = [HttpStatusCode]::OK
                    Body       = $Results
                })
        }

        $Results = Test-CIPPSAMSecret
    } catch {
        $Results = @{
            ready   = $false
            reason  = 'error'
            message = (Get-CippException -Exception $_).NormalizedError
        }
    }

    return ([HttpResponseContext]@{
            StatusCode = [HttpStatusCode]::OK
            Body       = $Results
        })
}
