# Pester tests for the External CSP connection test, which calls the provider's dedicated test URL.

BeforeAll {
    class HttpResponseContext {
        [int]$StatusCode
        [object]$Body
    }
    $TypeAccelerators = [PowerShell].Assembly.GetType('System.Management.Automation.TypeAccelerators')
    if (-not ([System.Management.Automation.PSTypeName]'HttpStatusCode').Type) {
        $TypeAccelerators::Add('HttpStatusCode', [System.Net.HttpStatusCode])
    }
    function Get-CIPPTable { param($TableName) @{} }
    function Get-CIPPAzDataTableEntity { param($Context) [pscustomobject]@{ config = '{}' } }
    function Invoke-ExternalCSPRequest { param($Action) }
    . "$PSScriptRoot/../../Modules/CIPPHTTP/Public/Entrypoints/HTTP Functions/CIPP/Extensions/Invoke-ExecExtensionTest.ps1"

    $script:Request = [pscustomobject]@{ Query = @{ extensionName = 'ExternalCSP' }; Headers = @{} }
}

Describe 'Invoke-ExecExtensionTest ExternalCSP' {
    It 'reports success when the test URL accepts the credentials' {
        Mock Invoke-ExternalCSPRequest { }
        $Response = Invoke-ExecExtensionTest -Request $script:Request
        $Response.StatusCode | Should -Be 200
        $Response.Body.Results | Should -Be 'Successfully connected to the CSP provider'
        Should -Invoke Invoke-ExternalCSPRequest -Times 1 -Exactly -ParameterFilter { $Action -eq 'Test' }
    }

    It 'reports a failure with the provider reason when the test URL refuses' {
        Mock Invoke-ExternalCSPRequest { throw 'The CSP provider rejected the Test request: Invalid API key' }
        $Response = Invoke-ExecExtensionTest -Request $script:Request
        $Response.StatusCode | Should -Be 500
        $Response.Body.Results | Should -BeLike 'Failed to connect*Invalid API key*'
    }
}
