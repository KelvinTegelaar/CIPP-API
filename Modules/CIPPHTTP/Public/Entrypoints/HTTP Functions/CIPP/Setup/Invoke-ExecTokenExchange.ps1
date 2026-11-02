function Invoke-ExecTokenExchange {
    <#
    .FUNCTIONALITY
        Entrypoint,AnyTenant
    .ROLE
        CIPP.AppSettings.ReadWrite
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    # Get the key vault name
    $KV = Get-CippKeyVaultName
    $APIName = $Request.Params.CIPPEndpoint

    if (!$Request.Body) {
        Write-LogMessage -API $APIName -message 'Request body is missing' -Sev 'Error'
        return ([HttpResponseContext]@{
                StatusCode = [HttpStatusCode]::BadRequest
                Body       = @{ error = 'invalid_request'; error_description = 'Request body is missing' }
                Headers    = @{'Content-Type' = 'application/json' }
            })
    }

    $TokenRequest = $Request.Body.tokenRequest
    $TokenUrl = $Request.Body.tokenUrl
    $TenantId = $Request.Body.tenantId

    if (!$TokenRequest -or !$TokenUrl) {
        Write-LogMessage -API $APIName -message 'Missing required parameters: tokenRequest or tokenUrl' -Sev 'Error'
        return ([HttpResponseContext]@{
                StatusCode = [HttpStatusCode]::BadRequest
                Body       = @{ error = 'invalid_request'; error_description = 'Missing required parameters: tokenRequest or tokenUrl' }
                Headers    = @{'Content-Type' = 'application/json' }
            })
    }

    # This endpoint exists only for the SAM setup wizard's authorization-code exchange, which always
    # posts to the /organizations token endpoint. Pin the full URL so a caller cannot redirect the
    # SAM credential to an arbitrary tenant realm.
    $ParsedTokenUri = $null
    $IsValidTokenUri = [System.Uri]::TryCreate($TokenUrl, [System.UriKind]::Absolute, [ref]$ParsedTokenUri)
    if (-not $IsValidTokenUri -or
        -not $ParsedTokenUri.Scheme.Equals('https', [System.StringComparison]::OrdinalIgnoreCase) -or
        -not $ParsedTokenUri.Host.Equals('login.microsoftonline.com', [System.StringComparison]::OrdinalIgnoreCase) -or
        -not $ParsedTokenUri.AbsolutePath.Equals('/organizations/oauth2/v2.0/token', [System.StringComparison]::OrdinalIgnoreCase)) {
        Write-LogMessage -API $APIName -message "Blocked token request to disallowed token endpoint: $TokenUrl" -Sev 'Warning'
        return ([HttpResponseContext]@{
                StatusCode = [HttpStatusCode]::BadRequest
                Body       = @{ error = 'invalid_request'; error_description = 'Invalid tokenUrl. Only https://login.microsoftonline.com/organizations/oauth2/v2.0/token is allowed.' }
                Headers    = @{'Content-Type' = 'application/json' }
            })
    }

    # Only the authorization-code grant is permitted. Any other grant (notably client_credentials)
    # would attach the SAM credential to a caller-chosen request and mint SAM tokens for any tenant.
    $GrantType = $TokenRequest.grant_type
    if ($GrantType -ne 'authorization_code') {
        Write-LogMessage -API $APIName -message "Blocked token exchange with disallowed grant_type: $GrantType" -Sev 'Warning'
        return ([HttpResponseContext]@{
                StatusCode = [HttpStatusCode]::BadRequest
                Body       = @{ error = 'unsupported_grant_type'; error_description = 'Only the authorization_code grant is supported.' }
                Headers    = @{'Content-Type' = 'application/json' }
            })
    }

    $StatusCode = [HttpStatusCode]::OK
    try {
        Write-LogMessage -API $APIName -message "Making token request to $TokenUrl" -Sev 'Info'

        # Make sure we get the latest authentication (also refreshes $env:CertificateAuthMode)
        $auth = Get-CIPPAuthentication

        # Forward only the fields the authorization-code exchange needs; never arbitrary caller fields.
        # The chosen credential (client secret or certificate assertion) is layered on top below.
        $AllowedFields = @('grant_type', 'client_id', 'code', 'redirect_uri', 'code_verifier', 'scope')
        $FormData = @{}
        foreach ($key in $TokenRequest.PSObject.Properties.Name) {
            if ($key -in $AllowedFields) {
                $FormData[$key] = $TokenRequest.$key
            }
        }

        # Bind client_id to this instance's SAM app when it is configured, so the exchange can only ever
        # run as CIPP's own app regardless of what the caller sends.
        if ($env:ApplicationID -and $env:ApplicationID -notmatch '^LongApplicationId$') {
            $FormData['client_id'] = $env:ApplicationID
        }

        # Resolve the client secret, tolerating its absence. A secret-less certificate-only setup
        # never has one, and certificate mode does not use it even when it exists.
        $ClientSecret = $null
        if ($auth -and $env:ApplicationSecret -and $env:ApplicationSecret -ne 'AppSecret') {
            $ClientSecret = $env:ApplicationSecret
        } elseif ($env:AzureWebJobsStorage -eq 'UseDevelopmentStorage=true' -or $env:NonLocalHostAzurite -eq 'true') {
            $DevSecretsTable = Get-CIPPTable -tablename 'DevSecrets'
            $Secret = Get-CIPPAzDataTableEntity @DevSecretsTable -Filter "PartitionKey eq 'Secret' and RowKey eq 'Secret'"
            $ClientSecret = $Secret.applicationsecret
        } else {
            try {
                $ClientSecret = (Get-CippKeyVaultSecret -VaultName $kv -Name 'applicationsecret' -AsPlainText)
            } catch {
                Write-LogMessage -API $APIName -message "Could not retrieve client secret (expected for a certificate-only setup): $($_.Exception.Message)" -Sev 'Debug'
            }
        }
        $SecretUsable = $ClientSecret -and $ClientSecret -ne 'AppSecret'

        # Use a signed certificate assertion instead of the client secret when certificate mode is
        # on, or when there is no usable secret at all (a secret-less setup - the only way to auth).
        $UseCertAssertion = [bool]$env:CertificateAuthMode -or -not $SecretUsable

        if ($UseCertAssertion) {
            $AppId = $FormData['client_id']
            if (!$AppId) {
                return ([HttpResponseContext]@{
                        StatusCode = [HttpStatusCode]::BadRequest
                        Body       = @{ error = 'invalid_request'; error_description = 'Token request is missing client_id; cannot build a certificate assertion.' }
                        Headers    = @{'Content-Type' = 'application/json' }
                    })
            }
            $SAMCert = Get-CIPPSAMCertificate -SkipCache
            if (-not $SAMCert) {
                throw 'Certificate authentication is required but no SAM certificate is available. Complete the application step first, then retry.'
            }
            # aud must equal the token endpoint we POST to (validated above). Do not use
            # $env:TenantID: the frontend posts to /organizations, and a partner-GUID aud
            # produces AADSTS700023. Body tenantId is the app id, not a realm.
            $FormData.Remove('client_secret')
            $FormData['client_assertion_type'] = 'urn:ietf:params:oauth:client-assertion-type:jwt-bearer'
            Write-LogMessage -API $APIName -message 'Using the SAM certificate assertion for the token exchange' -Sev 'Debug'
        } elseif (!$FormData.ContainsKey('client_secret')) {
            $FormData['client_secret'] = $ClientSecret
        }

        # AADSTS700027 fires transiently while a freshly registered certificate propagates - retry
        # briefly, regenerating the assertion each attempt so it never expires mid-retry.
        $MaxAttempts = if ($UseCertAssertion) { 3 } else { 1 }
        for ($Attempt = 1; $Attempt -le $MaxAttempts; $Attempt++) {
            if ($UseCertAssertion) {
                $FormData['client_assertion'] = New-CIPPCertificateAssertion -TenantId 'organizations' -AppId $AppId -Certificate $SAMCert.Certificate -Audience $TokenUrl
            }
            $Results = Invoke-RestMethod -Uri $TokenUrl -Method Post -Body $FormData -ContentType 'application/x-www-form-urlencoded' -ErrorAction Stop -SkipHttpErrorCheck
            if ($UseCertAssertion -and $Attempt -lt $MaxAttempts -and $Results.error_description -match 'AADSTS700027') {
                Write-LogMessage -API $APIName -message "Certificate not yet recognized by the token service (attempt $Attempt of $MaxAttempts). Retrying." -Sev 'Warning'
                Start-Sleep -Seconds 10
                continue
            }
            break
        }
    } catch {
        $StatusCode = [HttpStatusCode]::InternalServerError
        $ErrorMessage = $_.Exception
        $Results = @{
            error             = 'server_error'
            error_description = "Token exchange failed: $ErrorMessage"
        }
    }
    if ($Results.error -and $StatusCode -eq [HttpStatusCode]::OK) {
        # The token endpoint's own OAuth error (invalid_grant and the like) is passed through as a client error
        $StatusCode = [HttpStatusCode]::BadRequest
    }
    return ([HttpResponseContext]@{
            StatusCode = $StatusCode
            Body       = $Results
            Headers    = @{'Content-Type' = 'application/json' }
        })
}
