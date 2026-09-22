# Get-ClassicAPIToken is the second SAM-app token path (the classic v1 /oauth2/token endpoint used
# by New-ClassicAPIGetRequest). It must honour certificate-exclusive auth too, otherwise the flag
# would be enabled while classic API calls still sent the client secret. The v1 endpoint also needs
# the assertion audience to be the v1 token endpoint, not the default v2 one - pinned here.

BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))

    function Get-CIPPSAMCertificate { param([switch]$SkipCache) }
    function New-CIPPCertificateAssertion { param($TenantId, $AppId, $Certificate, $Audience) }
    function Invoke-CIPPRestMethod { param($Uri, $Body, $ContentType, $Method) }
    function Get-CippTable { param($tablename) }
    function Get-CIPPAzDataTableEntity { param($Context, $Filter) }
    function Update-AzDataTableEntity { param($Context, $Entity, [switch]$Force) }

    . (Join-Path $RepoRoot 'Modules/CIPPCore/Public/GraphHelper/Get-ClassicAPIToken.ps1')
}

Describe 'Get-ClassicAPIToken certificate-exclusive gating' {
    BeforeEach {
        $script:classictoken = $null # clear the per-key token cache between cases
        $script:SavedEnv = @{}
        foreach ($Name in 'CertificateAuthMode', 'ApplicationID', 'ApplicationSecret', 'TenantID', 'RefreshToken') {
            $script:SavedEnv[$Name] = [Environment]::GetEnvironmentVariable($Name)
        }
        $env:ApplicationID = 'sam-app-id'
        $env:ApplicationSecret = 'sam-secret'
        $env:RefreshToken = 'sam-refresh-token'
        $env:TenantID = '11111111-2222-3333-4444-555555555555'

        Mock Get-CIPPSAMCertificate { [pscustomobject]@{ Certificate = 'CERT-OBJECT' } }
        Mock New-CIPPCertificateAssertion { 'signed.jwt.assertion' }
        Mock Invoke-CIPPRestMethod { @{ access_token = 't'; expires_on = ([int](Get-Date -UFormat %s) + 3600) } }
        Mock Get-CippTable { @{} }
        Mock Get-CIPPAzDataTableEntity { $null }
        Mock Update-AzDataTableEntity {}
    }

    AfterEach {
        foreach ($Name in $script:SavedEnv.Keys) {
            if ($null -eq $script:SavedEnv[$Name]) { Remove-Item "env:$Name" -ErrorAction SilentlyContinue }
            else { Set-Item "env:$Name" -Value $script:SavedEnv[$Name] }
        }
    }

    It 'signs a certificate assertion (not the client secret) for the classic v1 endpoint when the flag is on' {
        $env:CertificateAuthMode = $true

        $null = Get-ClassicAPIToken -tenantID 'contoso.onmicrosoft.com' -Resource 'https://api.example.com'

        # The assertion audience must be the v1 token endpoint for the target tenant.
        Should -Invoke New-CIPPCertificateAssertion -Times 1 -Exactly -ParameterFilter {
            $Audience -eq 'https://login.microsoftonline.com/contoso.onmicrosoft.com/oauth2/token'
        }
        Should -Invoke Invoke-CIPPRestMethod -Times 1 -Exactly -ParameterFilter {
            $Body.ContainsKey('client_assertion') -and
            $Body['client_assertion_type'] -eq 'urn:ietf:params:oauth:client-assertion-type:jwt-bearer' -and
            -not $Body.ContainsKey('client_secret')
        }
    }

    It 'uses the client secret when the flag is off' {
        Remove-Item env:CertificateAuthMode -ErrorAction SilentlyContinue

        $null = Get-ClassicAPIToken -tenantID 'contoso.onmicrosoft.com' -Resource 'https://api.example.com'

        Should -Invoke New-CIPPCertificateAssertion -Times 0 -Exactly
        Should -Invoke Invoke-CIPPRestMethod -Times 1 -Exactly -ParameterFilter {
            $Body['client_secret'] -eq 'sam-secret' -and -not $Body.ContainsKey('client_assertion')
        }
    }
}
