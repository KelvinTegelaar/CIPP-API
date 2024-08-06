function Get-GraphTokenFromCert {
    param(
        [Parameter(Mandatory = $true)]
        [string]$TenantId,

        [Parameter(Mandatory = $true)]
        [string]$AppId,

        [string]$Scope = 'https://graph.microsoft.com/.default',
        [Parameter(Mandatory = $true)]
        [System.Security.Cryptography.X509Certificates.X509Certificate2]$Certificate
    )
    #########################################################
    # Create Bearer Token From Certificate for HBU Graph
    #########################################################

    # get sha256 hash of certificate
    $sha256 = New-Object System.Security.Cryptography.SHA256CryptoServiceProvider
    $hash = $sha256.ComputeHash($Certificate.RawData)
    $hash = [Convert]::ToBase64String($hash)

    # Create JWT timestamp for expiration
    $StartDate = (Get-Date '1970-01-01T00:00:00Z' ).ToUniversalTime()
    $JWTExpirationTimeSpan = (New-TimeSpan -Start $StartDate -End (Get-Date).ToUniversalTime().AddMinutes(2)).TotalSeconds
    $JWTExpiration = [math]::Round($JWTExpirationTimeSpan, 0)

    # Create JWT validity start timestamp
    $NotBeforeExpirationTimeSpan = (New-TimeSpan -Start $StartDate -End ((Get-Date).ToUniversalTime())).TotalSeconds
    $NotBefore = [math]::Round($NotBeforeExpirationTimeSpan, 0)

    # Create JWT header
    $JWTHeader = @{
        alg        = 'PS256'
        typ        = 'JWT'
        # Use the CertificateBase64Hash and replace/strip to match web encoding of base64
        'x5t#S256' = $hash -replace '\+', '-' -replace '/', '_' -replace '='
    }

    # Create JWT payload
    $JWTPayLoad = @{
        # Issuer = your application
        iss = $AppId

        # What endpoint is allowed to use this JWT
        aud = "https://login.microsoftonline.com/$TenantId/oauth2/v2.0/token"

        # JWT ID: random guid
        jti = [guid]::NewGuid()

        # Expiration timestamp
        exp = $JWTExpiration

        # Not to be used before
        nbf = $NotBefore

        # JWT Subject
        sub = $AppId
    }

    # Convert header and payload to base64
    $JWTHeaderToByte = [System.Text.Encoding]::UTF8.GetBytes(($JWTHeader | ConvertTo-Json))
    $EncodedHeader = [System.Convert]::ToBase64String($JWTHeaderToByte)

    $JWTPayLoadToByte = [System.Text.Encoding]::UTF8.GetBytes(($JWTPayload | ConvertTo-Json))
    $EncodedPayload = [System.Convert]::ToBase64String($JWTPayLoadToByte)

    # Join header and Payload with "." to create a valid (unsigned) JWT
    $JWT = $EncodedHeader + '.' + $EncodedPayload

    # Get the private key object of your certificate
    # $PrivateKey = $Certificate.PrivateKey
    $PrivateKey = ([System.Security.Cryptography.X509Certificates.RSACertificateExtensions]::GetRSAPrivateKey($Certificate))

    # Define RSA signature and hashing algorithm
    $RSAPadding = [Security.Cryptography.RSASignaturePadding]::Pss
    $HashAlgorithm = [Security.Cryptography.HashAlgorithmName]::SHA256

    # Create a signature of the JWT
    $Signature = [Convert]::ToBase64String(
        $PrivateKey.SignData([System.Text.Encoding]::UTF8.GetBytes($JWT), $HashAlgorithm, $RSAPadding)
    ) -replace '\+', '-' -replace '/', '_' -replace '='

    # Join the signature to the JWT with "."
    $JWT = $JWT + '.' + $Signature

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

    try {
        return Invoke-RestMethod @PostSplat
    } catch {
        Write-Error $_
    }

}
