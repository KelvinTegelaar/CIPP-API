# Pester tests for Invoke-ListAppsRepository
# The repository URL is caller-supplied: only public http(s) hosts may be fetched, on every redirect hop.

BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
    $FunctionPath = Get-ChildItem -Path (Join-Path $RepoRoot 'Modules') -Recurse -Filter 'Invoke-ListAppsRepository.ps1' -File | Select-Object -First 1 -ExpandProperty FullName

    class HttpResponseContext {
        [int]$StatusCode
        [object]$Body
    }
    class FakeRedirectException : System.Exception {
        [object]$Response
        FakeRedirectException([string]$Location) : base('redirect') { $this.Response = [pscustomobject]@{ Headers = [pscustomobject]@{ Location = [uri]$Location } } }
    }

    . ([ScriptBlock]::Create("using namespace System.Net`n" + (Get-Content -LiteralPath $FunctionPath -Raw)))
    . (Join-Path $RepoRoot 'Modules/CIPPCore/Public/Get-CippErrorStatusCode.ps1')

    function New-SearchRequest([string]$Repository) {
        [pscustomobject]@{ Params = @{ CIPPEndpoint = 'ListAppsRepository' }; Headers = @{}; Query = [pscustomobject]@{}; Body = [pscustomobject]@{ Search = 'git'; Repository = $Repository } }
    }
    $script:Feed = '<feed xmlns="http://www.w3.org/2005/Atom" xmlns:m="http://schemas.microsoft.com/ado/2007/08/dataservices/metadata" xmlns:d="http://schemas.microsoft.com/ado/2007/08/dataservices"><entry><title type="text">git</title><summary type="text">Git</summary><author><name>Git</name></author><m:properties><d:Title>Git</d:Title><d:Version>2.56.1</d:Version><d:Created m:type="Edm.DateTime">2026-11-11T00:13:57</d:Created></m:properties></entry></feed>'
}

Describe 'Invoke-ListAppsRepository repository URL' {
    It 'refuses <Repository> without fetching it' -ForEach @(
        @{ Repository = 'http://127.0.0.1:8080' }
        @{ Repository = 'http://169.254.169.254/metadata' }
        @{ Repository = 'http://10.1.2.3' }
        @{ Repository = 'http://[::1]' }
        @{ Repository = 'ftp://93.184.216.34' }
    ) {
        Mock Invoke-WebRequest { }

        $Response = Invoke-ListAppsRepository -Request (New-SearchRequest $Repository)

        $Response.StatusCode | Should -Be 400
        Should -Invoke Invoke-WebRequest -Times 0
    }

    It 'refuses a public repository that redirects to a local address' {
        Mock Invoke-WebRequest { throw [FakeRedirectException]::new('http://127.0.0.1/api/v2') }

        $Response = Invoke-ListAppsRepository -Request (New-SearchRequest 'https://93.184.216.34/api/v2')

        $Response.StatusCode | Should -Be 400
        Should -Invoke Invoke-WebRequest -Times 1 -Exactly
    }

    It 'follows a public redirect and returns the packages' {
        Mock Invoke-WebRequest { throw [FakeRedirectException]::new('https://93.184.216.35/api/v2/Search()') } -ParameterFilter { $Uri -like 'https://93.184.216.34/*' }
        Mock Invoke-WebRequest { [pscustomobject]@{ Content = $script:Feed } } -ParameterFilter { $Uri -like 'https://93.184.216.35/*' }

        $Response = Invoke-ListAppsRepository -Request (New-SearchRequest 'https://93.184.216.34/api/v2')

        $Response.StatusCode | Should -Be 200
        $Response.Body.Results.packagename | Should -Be 'git'
        $Response.Body.Results.version | Should -Be '2.56.1'
    }
}
