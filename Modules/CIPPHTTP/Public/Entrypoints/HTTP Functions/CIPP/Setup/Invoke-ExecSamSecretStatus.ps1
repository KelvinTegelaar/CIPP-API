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

        # Same placeholder set the deployment template seeds and Get-CIPPAuthentication skips.
        $PlaceholderPattern = '^(LongApplicationId|AppSecret|RefreshToken|tenantId)$'
        $Configured = $env:ApplicationID -and $env:ApplicationID -notmatch $PlaceholderPattern -and
        $env:ApplicationSecret -and $env:ApplicationSecret -notmatch $PlaceholderPattern -and
        $env:TenantID -and $env:TenantID -notmatch $PlaceholderPattern

        if (-not $Configured) {
            $Results = @{
                ready   = $false
                reason  = 'notConfigured'
                message = 'The application registration has not been created yet. Complete the application step first.'
            }
        } else {
            # A client credentials request is the cheapest way to ask Entra whether the secret is
            # live, and going direct deliberately bypasses CIPP's token cache - a token cached
            # before the secret was replaced would report ready when it is not. The authority has
            # to be tenant scoped; /common and /organizations do not accept this grant.
            $Body = @{
                client_id     = $env:ApplicationID
                client_secret = $env:ApplicationSecret
                scope         = 'https://graph.microsoft.com/.default'
                grant_type    = 'client_credentials'
            }
            $Response = Invoke-RestMethod -Uri "https://login.microsoftonline.com/$($env:TenantID)/oauth2/v2.0/token" -Method POST -Body $Body -ContentType 'application/x-www-form-urlencoded' -SkipHttpErrorCheck

            if ($Response.access_token) {
                $Results = @{ ready = $true; reason = 'ready' }
            } elseif ($Response.error_description -match 'AADSTS7000215') {
                $Results = @{
                    ready   = $false
                    reason  = 'propagating'
                    message = 'The application secret has been created but Microsoft has not finished activating it. This usually takes a few minutes and needs nothing recreating.'
                }
            } else {
                # Anything else is a real problem - a deleted secret, a disabled application -
                # and must not be presented as something waiting will fix.
                $Results = @{
                    ready   = $false
                    reason  = 'error'
                    message = $Response.error_description ?? 'The application secret could not be validated.'
                }
            }
        }
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
