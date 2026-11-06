# Entra answers a deleted client secret with the same AADSTS7000215 as one still activating, so the
# Status action has to tell them apart by whether the stored keyId is still on the SAM app.

BeforeAll {
    $BackendRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
    $FunctionPath = Join-Path $BackendRoot 'Modules/CIPPHTTP/Public/Entrypoints/HTTP Functions/CIPP/Setup/Invoke-ExecSAMCredentials.ps1'

    ([PSObject].Assembly.GetType('System.Management.Automation.TypeAccelerators')).GetMethod('Add').Invoke(
        $null, @('HttpStatusCode', [System.Net.HttpStatusCode]))

    class HttpResponseContext {
        [int]$StatusCode
        [object]$Body
    }

    function Get-CIPPTable { param($tablename) }
    function Get-CIPPSAMCredentials {}
    function Get-CIPPSAMCertificate { param([switch]$SkipCache) }
    function New-GraphGetRequest { param($uri, $tenantid, $NoAuthCheck, $AsApp) }
    function Get-CIPPFeatureFlag { param($Id) }
    function Test-CIPPSAMSecret { param([switch]$IncludeRefreshGrant) }
    function Get-GraphToken { param($ReturnRefresh, $TenantId, $SkipCache) }
    function Get-Tenants { param([switch]$IncludeAll) }
    function Write-LogMessage { param($headers, $API, $tenant, $message, $Sev, $LogData) }
    function Get-CippException { param($Exception) @{ NormalizedError = $Exception.Exception.Message } }

    . $FunctionPath

    $script:Request = [pscustomobject]@{ Params = @{ CIPPEndpoint = 'ExecSAMCredentials' }; Headers = @{}; Body = @{ Action = 'Status' }; Query = @{} }
}

Describe 'Invoke-ExecSAMCredentials Status stored secret' {
    BeforeEach {
        $script:SavedEnv = @{}
        foreach ($Name in 'ApplicationID', 'ApplicationSecret', 'TenantID', 'AzureWebJobsStorage', 'CertificateAuthMode') {
            $script:SavedEnv[$Name] = [Environment]::GetEnvironmentVariable($Name)
        }
        $env:ApplicationID = 'sam-app-id'
        $env:ApplicationSecret = 'real-secret'
        $env:TenantID = 'partner-tenant'
        $env:AzureWebJobsStorage = 'UseDevelopmentStorage=true'

        $script:CertMode = $false
        $script:AppSecrets = @()
        Mock Get-CIPPTable { @{} }
        Mock Get-CIPPSAMCredentials {
            [pscustomobject]@{ Credentials = $script:AppSecrets; OwnSecretKeyId = 'own-key'; OwnThumbprint = ''; StoredCertificate = $null }
        }
        Mock Get-CIPPFeatureFlag { [pscustomobject]@{ Enabled = $script:CertMode } }
        Mock New-GraphGetRequest { [pscustomobject]@{ verifiedDomains = @() } }
        Mock Test-CIPPSAMSecret { @{ ready = $false; reason = 'propagating'; message = 'still activating' } }
        Mock Get-GraphToken { 'token' }
        Mock Get-Tenants { @() }
    }

    AfterEach {
        foreach ($Name in $script:SavedEnv.Keys) { [Environment]::SetEnvironmentVariable($Name, $script:SavedEnv[$Name]) }
    }

    It 'reports a secret deleted from the app as removed in secret mode' {
        $Result = (Invoke-ExecSAMCredentials -Request $script:Request -TriggerMetadata $null).Body.Results

        $Result.storedSecret.state | Should -Be 'removed'
        $Result.overall | Should -Be 'tokenFailing'
    }

    It 'treats a secret deleted from the app as no secret in certificate mode' {
        $script:CertMode = $true

        $Result = (Invoke-ExecSAMCredentials -Request $script:Request -TriggerMetadata $null).Body.Results

        $Result.storedSecret.state | Should -Be 'none'
    }

    It 'keeps a secret that is still on the app as activating' {
        $script:AppSecrets = @([pscustomobject]@{ type = 'Secret'; keyId = 'own-key'; endDateTime = '2028-01-01T00:00:00Z' })

        $Result = (Invoke-ExecSAMCredentials -Request $script:Request -TriggerMetadata $null).Body.Results

        $Result.storedSecret.state | Should -Be 'propagating'
    }

    It 'keeps activating when the app credentials could not be read' {
        Mock Get-CIPPSAMCredentials { throw 'Graph unavailable' }

        $Result = (Invoke-ExecSAMCredentials -Request $script:Request -TriggerMetadata $null).Body.Results

        $Result.storedSecret.state | Should -Be 'propagating'
    }

    It 'trusts a working secret even when its keyId is not on the app' {
        Mock Test-CIPPSAMSecret { @{ ready = $true; reason = 'ready' } }

        $Result = (Invoke-ExecSAMCredentials -Request $script:Request -TriggerMetadata $null).Body.Results

        $Result.storedSecret.state | Should -Be 'valid'
    }
}
