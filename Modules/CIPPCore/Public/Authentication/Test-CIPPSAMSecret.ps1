function Test-CIPPSAMSecret {
    <#
    .SYNOPSIS
        Probes whether the stored SAM client secret can obtain a token right now.
    .DESCRIPTION
        Returns @{ ready; reason; message } where reason is ready, propagating (AADSTS7000215),
        notConfigured or error. Goes direct to Entra so a cached token cannot mask a dead secret.
    .FUNCTIONALITY
        Internal
    #>
    [CmdletBinding()]
    param(
        [string]$ApplicationId = $env:ApplicationID,
        [string]$ApplicationSecret = $env:ApplicationSecret,
        [string]$TenantId = $env:TenantID,
        # Also redeem the stored partner refresh token with the secret. That is the grant CIPP
        # actually runs on, and Entra activates a new secret for it separately from client_credentials.
        [switch]$IncludeRefreshGrant
    )

    # Same placeholder set the deployment template seeds and Get-CIPPAuthentication skips.
    $PlaceholderPattern = '^(LongApplicationId|AppSecret|RefreshToken|tenantId)$'
    $Configured = $ApplicationId -and $ApplicationId -notmatch $PlaceholderPattern -and
    $ApplicationSecret -and $ApplicationSecret -notmatch $PlaceholderPattern -and
    $TenantId -and $TenantId -notmatch $PlaceholderPattern

    if (-not $Configured) {
        return @{
            ready   = $false
            reason  = 'notConfigured'
            message = 'The application registration has not been created yet. Complete the application step first.'
        }
    }

    # The authority has to be tenant scoped; /common and /organizations do not accept this grant.
    $Body = @{
        client_id     = $ApplicationId
        client_secret = $ApplicationSecret
        scope         = 'https://graph.microsoft.com/.default'
        grant_type    = 'client_credentials'
    }
    $Response = Invoke-RestMethod -Uri "https://login.microsoftonline.com/$TenantId/oauth2/v2.0/token" -Method POST -Body $Body -ContentType 'application/x-www-form-urlencoded' -SkipHttpErrorCheck

    if ($Response.access_token -and $IncludeRefreshGrant -and $env:RefreshToken -and $env:RefreshToken -notmatch $PlaceholderPattern) {
        $RefreshBody = @{
            client_id     = $ApplicationId
            client_secret = $ApplicationSecret
            scope         = 'https://graph.microsoft.com/.default offline_access'
            grant_type    = 'refresh_token'
            refresh_token = $env:RefreshToken
        }
        $Response = Invoke-RestMethod -Uri "https://login.microsoftonline.com/$TenantId/oauth2/v2.0/token" -Method POST -Body $RefreshBody -ContentType 'application/x-www-form-urlencoded' -SkipHttpErrorCheck
    }
    if ($Response.access_token) {
        return @{ ready = $true; reason = 'ready' }
    }
    if ($Response.error_description -match 'AADSTS7000215') {
        return @{
            ready   = $false
            reason  = 'propagating'
            message = 'The application secret has been created but Microsoft has not finished activating it. This usually takes a few minutes and needs nothing recreating.'
        }
    }
    # Anything else (deleted secret, disabled app) is not something waiting will fix.
    return @{
        ready   = $false
        reason  = 'error'
        message = $Response.error_description ?? 'The application secret could not be validated.'
    }
}
