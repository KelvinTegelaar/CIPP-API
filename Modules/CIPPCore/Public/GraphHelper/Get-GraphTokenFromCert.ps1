function Get-GraphTokenFromCert {
    param(
        [Parameter(Mandatory = $true)]
        [string]$TenantId,

        [Parameter(Mandatory = $true)]
        [string]$AppId,

        [string]$Scope = 'https://graph.microsoft.com/.default',
        [Parameter(Mandatory = $true)]
        [System.Security.Cryptography.X509Certificates.X509Certificate2]$Certificate,
        [switch]$SkipCache
    )
    #########################################################
    # Create Bearer Token From Certificate for HBU Graph
    #########################################################

    # Check the token cache before building a new assertion. Uses the shared .NET cache when
    # loaded (cross-runspace), otherwise a script-scope fallback (local dev).
    $UseSharedTokenCache = ($SkipCache -ne $true) -and ($null -ne ('CIPP.CIPPTokenCache' -as [type]))
    if ($UseSharedTokenCache) {
        $TokenCacheKey = [CIPP.CIPPTokenCache]::BuildKey([string]$TenantId, [string]$Scope, $true, [string]$AppId, 'client_credentials_certificate')
        $CacheEntry = [CIPP.CIPPTokenCache]::Lookup($TokenCacheKey, 120)
        if ($CacheEntry.Found -and -not [string]::IsNullOrWhiteSpace($CacheEntry.TokenPayloadJson)) {
            try {
                return ($CacheEntry.TokenPayloadJson | ConvertFrom-Json -ErrorAction Stop)
            } catch {
                [CIPP.CIPPTokenCache]::Remove($TokenCacheKey)
            }
        }
    } elseif ($SkipCache -ne $true) {
        $ScriptCacheKey = "$TenantId|$AppId|$Scope"
        $Cached = $script:CertTokenCache.$ScriptCacheKey
        if ($Cached.expires_on -and [int](Get-Date -UFormat %s -Millisecond 0) -lt ($Cached.expires_on - 120)) {
            return $Cached
        }
    }

    # Build the signed client assertion (shared with Get-GraphToken -UseCertificate)
    $JWT = New-CIPPCertificateAssertion -TenantId $TenantId -AppId $AppId -Certificate $Certificate

    # Create a hash with body parameters
    $Body = @{
        client_id             = $AppId
        client_assertion      = $JWT
        client_assertion_type = 'urn:ietf:params:oauth:client-assertion-type:jwt-bearer'
        scope                 = $Scope
        grant_type            = 'client_credentials'
    }

    $Url = "https://login.microsoftonline.com/$TenantId/oauth2/v2.0/token"

    # Use the self-generated JWT as Authorization
    $Header = @{
        Authorization = "Bearer $JWT"
    }

    # Splat the parameters for Invoke-Restmethod for cleaner code
    $PostSplat = @{
        ContentType = 'application/x-www-form-urlencoded'
        Method      = 'POST'
        Body        = $Body
        Uri         = $Url
        Headers     = $Header
    }

    # AADSTS700027 occurs transiently after certificate rotation while the load-balanced
    # token service nodes catch up with the directory - retry briefly before giving up.
    $MaxRetries = 3
    for ($Attempt = 1; $Attempt -le $MaxRetries; $Attempt++) {
        try {
            $AccessToken = Invoke-CIPPRestMethod @PostSplat -ErrorAction Stop
            if ($AccessToken.access_token) {
                if ($null -eq $AccessToken.expires_on -and $AccessToken.expires_in) {
                    $ExpiresOn = [int](Get-Date -UFormat %s -Millisecond 0) + $AccessToken.expires_in
                    Add-Member -InputObject $AccessToken -NotePropertyName 'expires_on' -NotePropertyValue $ExpiresOn -Force
                }
                if ($UseSharedTokenCache) {
                    try {
                        [CIPP.CIPPTokenCache]::Store($TokenCacheKey, ($AccessToken | ConvertTo-Json -Depth 20 -Compress), [int64]$AccessToken.expires_on)
                    } catch {
                        # Ignore shared cache write failures
                    }
                } elseif ($SkipCache -ne $true) {
                    if (-not $script:CertTokenCache) { $script:CertTokenCache = [HashTable]::Synchronized(@{}) }
                    $script:CertTokenCache.$ScriptCacheKey = $AccessToken
                }
            }
            return $AccessToken
        } catch {
            if ($Attempt -lt $MaxRetries -and $_.ErrorDetails.Message -match 'AADSTS700027') {
                Write-Warning "Certificate not yet recognized by the token service (attempt $Attempt of $MaxRetries). Retrying in 10 seconds."
                Start-Sleep -Seconds 10
            } else {
                Write-Error $_
                return
            }
        }
    }

}
