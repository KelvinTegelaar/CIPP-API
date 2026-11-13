BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))

    function Invoke-CIPPRestMethod { param($Uri, $Body, $ContentType, $Method) }

    . (Join-Path $RepoRoot 'Modules/CIPPCore/Public/GraphHelper/Get-ClassicAPIToken.ps1')
}

Describe 'Get-ClassicAPIToken token cache' {
    BeforeEach {
        $script:SavedCertificateAuthMode = $env:CertificateAuthMode
        Remove-Item env:CertificateAuthMode -ErrorAction SilentlyContinue
        $script:classictoken = [hashtable]::Synchronized(@{})
        Mock Invoke-CIPPRestMethod { [pscustomobject]@{ access_token = 'new'; expires_on = "$([DateTimeOffset]::UtcNow.ToUnixTimeSeconds() + 3600)" } }
    }

    AfterEach {
        if ($null -ne $script:SavedCertificateAuthMode) { $env:CertificateAuthMode = $script:SavedCertificateAuthMode }
    }

    It 'removes expired tokens from the shared cache when it stores a new one' {
        $Shared = $script:classictoken
        $Now = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds()
        foreach ($i in 1..500) { $Shared["tenant$i-https://api.example.com"] = [pscustomobject]@{ access_token = 'old'; expires_on = "$($Now - 10)" } }
        $Shared['live-https://api.example.com'] = [pscustomobject]@{ access_token = 'live'; expires_on = "$($Now + 3600)" }

        (Get-ClassicAPIToken -tenantID 'contoso.onmicrosoft.com' -Resource 'https://api.example.com').access_token | Should -Be 'new'

        [object]::ReferenceEquals($script:classictoken, $Shared) | Should -BeTrue
        @($Shared.Keys | Sort-Object) | Should -Be @('contoso.onmicrosoft.com-https://api.example.com', 'live-https://api.example.com')
    }
}
