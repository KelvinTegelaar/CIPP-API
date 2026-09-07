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

    try {
        if (!$Request.Body) {
            Write-LogMessage -API $APIName -message 'Request body is missing' -Sev 'Error'
            throw 'Request body is missing'
        }

        $TokenRequest = $Request.Body.tokenRequest
        $TokenUrl = $Request.Body.tokenUrl
        $TenantId = $Request.Body.tenantId

        if (!$TokenRequest -or !$TokenUrl) {
            Write-LogMessage -API $APIName -message 'Missing required parameters: tokenRequest or tokenUrl' -Sev 'Error'
            throw 'Missing required parameters: tokenRequest or tokenUrl'
        }

        $ParsedTokenUri = $null
        $IsValidTokenUri = [System.Uri]::TryCreate($TokenUrl, [System.UriKind]::Absolute, [ref]$ParsedTokenUri)
        if (-not $IsValidTokenUri -or
            -not $ParsedTokenUri.Scheme.Equals('https', [System.StringComparison]::OrdinalIgnoreCase) -or
            -not $ParsedTokenUri.Host.Equals('login.microsoftonline.com', [System.StringComparison]::OrdinalIgnoreCase)) {
            Write-LogMessage -API $APIName -message "Blocked token request to non-Microsoft login host: $TokenUrl" -Sev 'Warning'
            throw 'Invalid tokenUrl. Only https://login.microsoftonline.com is allowed.'
        }

        Write-LogMessage -API $APIName -message "Making token request to $TokenUrl" -Sev 'Info'

        # Make sure we get the latest authentication (also refreshes $env:CertificateAuthMode)
        $auth = Get-CIPPAuthentication

        # Convert the token request to form data first, so the chosen credential - client secret
        # or certificate assertion - can be layered on top.
        $FormData = @{}
        foreach ($key in $TokenRequest.PSObject.Properties.Name) {
            $FormData[$key] = $TokenRequest.$key
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
            if (!$AppId) { throw 'Token request is missing client_id; cannot build a certificate assertion.' }
            $SAMCert = Get-CIPPSAMCertificate -SkipCache
            if (-not $SAMCert) {
                throw 'Certificate authentication is required but no SAM certificate is available. Complete the application step first, then retry.'
            }
            # Assertion audience = the tenant the sign-in targets ($env:TenantID). The body's tenantId is
            # actually the app id, so it is not a valid audience; fall back to the multi-tenant authority.
            $GuidPattern = '^[0-9a-f]{8}-([0-9a-f]{4}-){3}[0-9a-f]{12}$'
            $AssertionTenant = if ($env:TenantID -match $GuidPattern) { $env:TenantID } else { 'organizations' }
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
                $FormData['client_assertion'] = New-CIPPCertificateAssertion -TenantId $AssertionTenant -AppId $AppId -Certificate $SAMCert.Certificate
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
        $ErrorMessage = $_.Exception
        $Results = @{
            error             = 'server_error'
            error_description = "Token exchange failed: $ErrorMessage"
        }
    }
    if ($Results.error) {
        return ([HttpResponseContext]@{
                StatusCode = [HttpStatusCode]::BadRequest
                Body       = $Results
                Headers    = @{'Content-Type' = 'application/json' }
            })
    } else {
        return ([HttpResponseContext]@{
                StatusCode = [HttpStatusCode]::OK
                Body       = $Results
                Headers    = @{'Content-Type' = 'application/json' }
            })
    }
}
