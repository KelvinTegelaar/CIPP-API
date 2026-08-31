# The certificate-exclusive auth flag lets CIPP authenticate its SAM application with the SAM
# certificate instead of the client secret. Two invariants must never regress:
#   1. When the flag is on, the SAM app's own tokens (app-only AND delegated) use the certificate.
#   2. It is scoped to the SAM app only - callers passing an explicit $AppID/$AppSecret authenticate
#      a different application whose registration does not carry the SAM certificate, so they must
#      keep using the secret even while the flag is on.
# A regression in either direction is a broad authentication outage, so both are pinned here.

BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))

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

    . (Join-Path $RepoRoot 'Modules/CIPPCore/Public/GraphHelper/Get-GraphToken.ps1')
}

Describe 'Get-GraphToken certificate-exclusive gating' {
    BeforeEach {
        # A clean, non-direct-tenant environment: the tenant we ask for equals $env:TenantID so the
        # direct-tenant refresh-token branch is never taken.
        $script:SavedEnv = @{}
        foreach ($Name in 'CertificateAuthMode', 'ApplicationID', 'ApplicationSecret', 'TenantID', 'RefreshToken', 'SetFromProfile') {
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
}
