# The certificate-exclusive auth flag lets CIPP authenticate its SAM application with the SAM
# certificate instead of the client secret. Two invariants must never regress:
#   1. When the flag is on, the SAM app's own tokens (app-only AND delegated) use the certificate.
#   2. It is scoped to the SAM app only - callers passing an explicit $AppID/$AppSecret authenticate
#      a different application whose registration does not carry the SAM certificate, so they must
#      keep using the secret even while the flag is on.
# A regression in either direction is a broad authentication outage, so both are pinned here.

BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
    if (-not ('CIPP.CIPPTokenCache' -as [type])) {
        Add-Type -Path (Join-Path $RepoRoot 'Shared/CIPPSharp/bin/CIPPSharp.dll')
    }

    function Get-CIPPAuthentication { $true }
    function Get-CippTable { param($tablename) }
    function Get-CIPPAzDataTableEntity { param($Context, $Filter, $Property) }
    function Add-CIPPAzDataTableEntity { param($Context, $Entity, [switch]$Force) }
    function Update-AzDataTableEntity { param($Context, $Entity, [switch]$Force) }
    function Get-CIPPSAMCertificate { param([switch]$SkipCache) }
    function Get-GraphTokenFromCert { param($TenantId, $AppId, $Scope, $Certificate, [switch]$SkipCache) }
    function New-CIPPCertificateAssertion { param($TenantId, $AppId, $Certificate) }
    function Invoke-CIPPRestMethod { param($Method, $Uri, $Body, $ContentType) }
    function Get-CippKeyVaultName {}
    function Get-CippKeyVaultSecret { param($VaultName, $Name, [switch]$AsPlainText) }
    function Update-CIPPSAMCertificateEnvCache { param($Name, $PfxBase64) }

    . (Join-Path $RepoRoot 'Modules/CIPPCore/Public/GraphHelper/Get-GraphToken.ps1')
}

Describe 'Get-GraphToken certificate-exclusive gating' {
    BeforeEach {
        $null = [CIPP.CIPPTokenCache]::Clear()
        # A clean, non-direct-tenant environment: the tenant we ask for equals $env:TenantID so the
        # direct-tenant refresh-token branch is never taken.
        $script:SavedEnv = @{}
        foreach ($Name in 'CertificateAuthMode', 'ApplicationID', 'ApplicationSecret', 'TenantID', 'RefreshToken', 'SetFromProfile', 'CIPPCredentialVersion') {
            $script:SavedEnv[$Name] = [Environment]::GetEnvironmentVariable($Name)
        }
        $env:ApplicationID = 'sam-app-id'
        $env:ApplicationSecret = 'sam-secret'
        $env:TenantID = '11111111-2222-3333-4444-555555555555'
        $env:RefreshToken = 'sam-refresh-token'
        $env:SetFromProfile = 'true' # skip the Get-CIPPAuthentication reload inside the function

        Mock Get-CippTable { @{} }
        Mock Get-CIPPAzDataTableEntity { $null }
        Mock Add-CIPPAzDataTableEntity {}
        Mock Update-AzDataTableEntity {}
        Mock Get-CIPPSAMCertificate { [pscustomobject]@{ Certificate = 'CERT-OBJECT'; Thumbprint = 'ABC' } }
        Mock Get-GraphTokenFromCert { @{ access_token = 'cert-token'; expires_in = 3600 } }
        Mock New-CIPPCertificateAssertion { 'signed.jwt.assertion' }
        Mock Invoke-CIPPRestMethod { @{ access_token = 'secret-token'; expires_in = 3600 } }
    }

    AfterEach {
        foreach ($Name in $script:SavedEnv.Keys) {
            if ($null -eq $script:SavedEnv[$Name]) {
                Remove-Item "env:$Name" -ErrorAction SilentlyContinue
            } else {
                Set-Item "env:$Name" -Value $script:SavedEnv[$Name]
            }
        }
    }

    It 'uses the certificate for an app-only SAM token when the flag is on' {
        $env:CertificateAuthMode = $true

        $null = Get-GraphToken -AsApp $true

        Should -Invoke Get-GraphTokenFromCert -Times 1 -Exactly
        Should -Invoke Invoke-CIPPRestMethod -Times 0 -Exactly
    }

    It 'uses a certificate assertion (not the client secret) for a delegated SAM token when the flag is on' {
        $env:CertificateAuthMode = $true

        $null = Get-GraphToken

        Should -Invoke New-CIPPCertificateAssertion -Times 1 -Exactly
        Should -Invoke Get-GraphTokenFromCert -Times 0 -Exactly
        Should -Invoke Invoke-CIPPRestMethod -Times 1 -Exactly -ParameterFilter {
            $Body.ContainsKey('client_assertion') -and
            $Body['client_assertion_type'] -eq 'urn:ietf:params:oauth:client-assertion-type:jwt-bearer' -and
            -not $Body.ContainsKey('client_secret')
        }
    }

    It 'still uses the client secret when the flag is off' {
        Remove-Item env:CertificateAuthMode -ErrorAction SilentlyContinue

        $null = Get-GraphToken -AsApp $true

        Should -Invoke Get-GraphTokenFromCert -Times 0 -Exactly
        Should -Invoke Invoke-CIPPRestMethod -Times 1 -Exactly -ParameterFilter {
            $Body['client_secret'] -eq 'sam-secret' -and -not $Body.ContainsKey('client_assertion')
        }
    }

    It 'does NOT use the SAM certificate for a different app passed with an explicit AppID/AppSecret, even when the flag is on' {
        # This is the guard: the SAM certificate is not registered on an arbitrary application, so
        # forcing it here would break every extension/other-app token. The explicit secret must win.
        $env:CertificateAuthMode = $true

        $null = Get-GraphToken -AppID 'other-app-id' -AppSecret 'other-app-secret'

        Should -Invoke Get-GraphTokenFromCert -Times 0 -Exactly
        Should -Invoke New-CIPPCertificateAssertion -Times 0 -Exactly
        Should -Invoke Invoke-CIPPRestMethod -Times 1 -Exactly -ParameterFilter {
            $Body['client_id'] -eq 'other-app-id' -and
            $Body['client_secret'] -eq 'other-app-secret' -and
            -not $Body.ContainsKey('client_assertion')
        }
    }
    It 'holds an invalid-client-secret failure for about a minute, not the 30 minutes other admin errors get' {
        Mock Get-CIPPAzDataTableEntity { param($Context, $Filter, $Property) if ($Filter -like "*Tenants*" -and $Filter -notlike "*directTenant*") { [pscustomobject]@{ RowKey = 't'; LastGraphError = ''; LastGraphTokenError = '' } } }
        Mock Invoke-CIPPRestMethod { throw 'invalid_client:AADSTS7000215: Invalid client secret provided.' }
        $Key = [CIPP.CIPPTokenCache]::BuildKey($env:TenantID, 'https://graph.microsoft.com/.default', $false, $env:ApplicationID, 'refresh_token')

        { Get-GraphToken } | Should -Throw '*AADSTS7000215*'

        $Failure = [CIPP.CIPPTokenCache]::Lookup("$Key|failed", 0)
        $Failure.Found | Should -BeTrue
        ($Failure.ExpiresOnUnix - [DateTimeOffset]::UtcNow.ToUnixTimeSeconds()) | Should -BeLessOrEqual 60
    }
}

Describe 'Get-GraphToken stale SAM certificate self-heal' {
    BeforeEach {
        $null = [CIPP.CIPPTokenCache]::Clear()
        $script:SavedEnv = @{}
        foreach ($Name in 'CertificateAuthMode', 'ApplicationID', 'ApplicationSecret', 'TenantID', 'RefreshToken', 'SetFromProfile') {
            $script:SavedEnv[$Name] = [Environment]::GetEnvironmentVariable($Name)
        }
        $env:ApplicationID = 'sam-app-id'
        $env:ApplicationSecret = 'sam-secret'
        $env:TenantID = '11111111-2222-3333-4444-555555555555'
        $env:RefreshToken = 'sam-refresh-token'
        $env:SetFromProfile = 'true'
        $env:CertificateAuthMode = $true

        Mock Get-CippTable { @{} }
        Mock Get-CIPPAzDataTableEntity { $null }
        Mock Update-AzDataTableEntity {}
        Mock Update-CIPPSAMCertificateEnvCache {}
        # The runspace cache serves an old cert; storage holds the registered one.
        Mock Get-CIPPSAMCertificate { [pscustomobject]@{ Certificate = 'OLD-CERT'; Thumbprint = 'OLD' } }
        Mock Get-CIPPSAMCertificate { [pscustomobject]@{ Certificate = 'NEW-CERT'; Thumbprint = 'NEW'; PfxBase64 = 'NEW-PFX' } } -ParameterFilter { $SkipCache }
        Mock Get-GraphTokenFromCert { throw 'AADSTS700027: Client assertion contains an invalid signature.' } -ParameterFilter { $Certificate -eq 'OLD-CERT' }
        Mock Get-GraphTokenFromCert { @{ access_token = 'new-cert-token'; expires_in = 3600 } } -ParameterFilter { $Certificate -eq 'NEW-CERT' }
        Mock New-CIPPCertificateAssertion { "assertion-for-$Certificate" }
        Mock Invoke-CIPPRestMethod {
            if ($Body['client_assertion'] -eq 'assertion-for-OLD-CERT') { throw 'AADSTS700027: Client assertion contains an invalid signature.' }
            @{ access_token = 'delegated-token'; expires_in = 3600 }
        }
    }

    AfterEach {
        foreach ($Name in $script:SavedEnv.Keys) {
            if ($null -eq $script:SavedEnv[$Name]) {
                Remove-Item "env:$Name" -ErrorAction SilentlyContinue
            } else {
                Set-Item "env:$Name" -Value $script:SavedEnv[$Name]
            }
        }
    }

    It 'retries an app-only token once with the stored certificate when the cached one is rejected' {
        $Result = Get-GraphToken -AsApp $true

        $Result.Authorization | Should -Be 'Bearer new-cert-token'
        Should -Invoke Get-GraphTokenFromCert -Times 2 -Exactly
        Should -Invoke Update-CIPPSAMCertificateEnvCache -Times 1 -Exactly -ParameterFilter { $PfxBase64 -eq 'NEW-PFX' }
    }

    It 'retries a delegated token once with an assertion signed by the stored certificate' {
        $Result = Get-GraphToken

        $Result.Authorization | Should -Be 'Bearer delegated-token'
        Should -Invoke Invoke-CIPPRestMethod -Times 2 -Exactly
    }

    It 'propagates the error when the stored certificate is the one that was rejected' {
        Mock Get-CIPPSAMCertificate { [pscustomobject]@{ Certificate = 'OLD-CERT'; Thumbprint = 'OLD' } } -ParameterFilter { $SkipCache }

        { Get-GraphToken -AsApp $true } | Should -Throw '*AADSTS700027*'
        Should -Invoke Get-GraphTokenFromCert -Times 1 -Exactly
    }

    It 'reloads credentials when the AppCache CredentialVersion differs from this runspace' {
        $env:CIPPCredentialVersion = 'v1'
        Mock Get-CIPPAuthentication { $true }
        Mock Get-CIPPAzDataTableEntity { param($Context, $Filter, $Property) if ($Filter -like "*AppCache*") { [pscustomobject]@{ ApplicationId = 'sam-app-id'; CredentialVersion = 'v2' } } }

        $null = Get-GraphToken -AsApp $true

        Should -Invoke Get-CIPPAuthentication -Times 1 -Exactly
        $env:CIPPCredentialVersion | Should -Be 'v2'
    }

    It 'does not reload when the CredentialVersion already matches' {
        $env:CIPPCredentialVersion = 'v2'
        Mock Get-CIPPAuthentication { $true }
        Mock Get-CIPPAzDataTableEntity { param($Context, $Filter, $Property) if ($Filter -like "*AppCache*") { [pscustomobject]@{ ApplicationId = 'sam-app-id'; CredentialVersion = 'v2' } } }

        $null = Get-GraphToken -AsApp $true

        Should -Invoke Get-CIPPAuthentication -Times 0 -Exactly
    }
}
