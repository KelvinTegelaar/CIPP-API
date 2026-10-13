# Certificate auth switches every SAM token onto the certificate, so both setup entrypoints must
# leave the flag off unless the certificate has proven it can obtain a token.

BeforeAll {
    $BackendRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
    $SetupRoot = Join-Path $BackendRoot 'Modules/CIPPHTTP/Public/Entrypoints/HTTP Functions/CIPP/Setup'

    ([PSObject].Assembly.GetType('System.Management.Automation.TypeAccelerators')).GetMethod('Add').Invoke(
        $null, @('HttpStatusCode', [System.Net.HttpStatusCode]))

    class HttpResponseContext {
        [int]$StatusCode
        [object]$Body
    }

    function Get-CIPPAuthentication {}
    function Get-CippKeyVaultName {}
    function Set-CippKeyVaultSecret { param($VaultName, $Name, $SecretValue) }
    function Update-CIPPSAMCertificate { param($ApplicationId, $Headers) }
    function Get-CIPPSAMCertificate { param([switch]$SkipCache) }
    function Test-CIPPSAMCertificateAuth { param($ApplicationId, $TenantId) }
    function Set-CIPPFeatureFlag { param($Id, $Enabled, [switch]$Force) }
    function Update-AppManagementPolicy { param($Headers, $ApplicationId, $CertificateOnly) }
    function Write-LogMessage { param($headers, $API, $tenant, $message, $Sev, $LogData) }
    function Get-NormalizedError { param($message) $message }

    . (Join-Path $SetupRoot 'Invoke-ExecCombinedSetup.ps1')
    . (Join-Path $SetupRoot 'Invoke-ExecCreateSAMApp.ps1')
}

Describe 'Certificate auth enable gate' {
    BeforeEach {
        $script:SavedEnv = @{}
        foreach ($Name in 'CertificateAuthMode', 'CIPPRootPath', 'ApplicationID', 'TenantID', 'ApplicationSecret') {
            $script:SavedEnv[$Name] = [Environment]::GetEnvironmentVariable($Name)
        }
        Remove-Item env:CertificateAuthMode -ErrorAction SilentlyContinue
        $env:CIPPRootPath = $BackendRoot

        Mock Get-CIPPAuthentication { $true }
        Mock Update-CIPPSAMCertificate { [pscustomobject]@{ Thumbprint = 'ABC123' } }
        Mock Get-CIPPSAMCertificate { [pscustomobject]@{ Thumbprint = 'ABC123' } }
        Mock Set-CIPPFeatureFlag {}
        Mock Set-CippKeyVaultSecret {}
        Mock Update-AppManagementPolicy { @{ PolicyAction = $null } }
        Mock Write-LogMessage {}
        Mock Test-CIPPSAMCertificateAuth { [pscustomobject]@{ Success = $false; Thumbprint = 'ABC123'; Error = 'AADSTS700027: invalid signature' } }
        Mock Invoke-RestMethod {
            if ($Uri -like '*/organization') { return @{ value = @(@{ id = 'tenant-guid' }) } }
            if ($Uri -like '*/applications?*') { return @{ value = @([pscustomobject]@{ id = 'app-object-id'; appId = 'app-guid' }) } }
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

    It 'ExecCombinedSetup leaves certificate auth off when the certificate cannot obtain a token' {
        $Response = Invoke-ExecCombinedSetup -Request ([pscustomobject]@{ Body = [pscustomobject]@{ certificateAuth = $true }; Headers = @{} }) -TriggerMetadata $null

        Should -Invoke Set-CIPPFeatureFlag -Times 0 -Exactly
        $env:CertificateAuthMode | Should -BeNullOrEmpty
        ($Response.Body -join ' ') | Should -BeLike '*ABC123 could not obtain a token (AADSTS700027*The client secret remains in use*'
    }

    It 'ExecCombinedSetup enables certificate auth when the certificate obtains a token' {
        Mock Test-CIPPSAMCertificateAuth { [pscustomobject]@{ Success = $true; Thumbprint = 'ABC123'; Error = $null } }

        $null = Invoke-ExecCombinedSetup -Request ([pscustomobject]@{ Body = [pscustomobject]@{ certificateAuth = $true }; Headers = @{} }) -TriggerMetadata $null

        Should -Invoke Set-CIPPFeatureFlag -Times 1 -Exactly -ParameterFilter { $Enabled -eq $true }
        $env:CertificateAuthMode | Should -Be 'True'
    }

    It 'ExecCreateSAMApp rolls certificate auth back and fails a certificate-only setup when the certificate cannot obtain a token' {
        $Request = [pscustomobject]@{
            Body    = [pscustomobject]@{ access_token = 'delegated'; certificateOnly = $true }
            Headers = @{ origin = 'https://cipp.example' }
            Params  = @{ CIPPEndpoint = 'ExecCreateSAMApp' }
        }

        $Response = Invoke-ExecCreateSAMApp -Request $Request -TriggerMetadata $null

        $Response.StatusCode | Should -Be 500
        $Response.Body.Results | Should -BeLike '*could not obtain a token*'
        Should -Invoke Test-CIPPSAMCertificateAuth -Times 1 -Exactly -ParameterFilter { $ApplicationId -eq 'app-guid' -and $TenantId -eq 'tenant-guid' }
        Should -Invoke Set-CIPPFeatureFlag -Times 1 -Exactly -ParameterFilter { $Enabled -eq $false }
        Should -Invoke Set-CippKeyVaultSecret -Times 0 -Exactly
        $env:CertificateAuthMode | Should -BeNullOrEmpty
    }
}
