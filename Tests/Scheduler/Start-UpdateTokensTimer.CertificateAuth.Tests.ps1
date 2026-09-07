# The weekly token timer renews the SAM app's client secret. In certificate-exclusive mode CIPP adds
# no secret, so the timer must NOT call addPassword - otherwise it fails on tenants blocking password
# addition, or silently re-creates a secret on a secret-less install, defeating the feature. Pinned here.

BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))

    function Get-GraphToken { param([switch]$ReturnRefresh, $TenantId) }
    function Get-CIPPTable { param($tablename) }
    function Get-CIPPAzDataTableEntity { param($Context, $Filter) }
    function Get-Tenants { param([switch]$IncludeAll, [switch]$SkipList) }
    function Add-AzDataTableEntity { param($Context, $Entity, [switch]$Force) }
    function New-GraphGetRequest { param($uri, $NoAuthCheck, $AsApp) }
    function New-GraphPostRequest { param($uri, $type, $Body, $NoAuthCheck, $AsApp) }
    function Update-AppManagementPolicy {}
    function Update-CIPPSAMCertificate {}
    function Write-LogMessage { param($API, $message, $sev, $tenant, $tenantid, $LogData) }
    function Get-CippException { param($Exception) }

    . (Join-Path $RepoRoot 'Modules/CIPPCore/Public/Entrypoints/Timer Functions/Start-UpdateTokensTimer.ps1')
}

Describe 'Start-UpdateTokensTimer certificate mode' {
    BeforeEach {
        $script:SavedEnv = @{}
        foreach ($Name in 'CertificateAuthMode', 'ApplicationID', 'TenantID', 'AzureWebJobsStorage') { $script:SavedEnv[$Name] = [Environment]::GetEnvironmentVariable($Name) }
        $env:ApplicationID = 'sam-app-id'
        $env:TenantID = '11111111-2222-3333-4444-555555555555'
        $env:AzureWebJobsStorage = 'UseDevelopmentStorage=true' # dev branch - no Key Vault

        Mock Get-GraphToken { @{ Refresh_token = 'refresh-token' } }
        Mock Get-CIPPTable { @{} }
        Mock Get-CIPPAzDataTableEntity { $null }   # no dev secret row, no direct tenants
        Mock Get-Tenants { @() }                    # no direct tenants to refresh
        Mock Add-AzDataTableEntity {}
        # Secret-less install: the app registration has no password credentials.
        Mock New-GraphGetRequest {
            [pscustomobject]@{ id = 'app-obj-id'; passwordCredentials = @(); servicePrincipalLockConfiguration = [pscustomobject]@{ isEnabled = $true } }
        }
        Mock New-GraphPostRequest { [pscustomobject]@{ secretText = 's'; keyId = 'k'; endDateTime = (Get-Date).AddYears(1) } }
        Mock Update-AppManagementPolicy { [pscustomobject]@{ PolicyAction = 'none' } }
        Mock Update-CIPPSAMCertificate { [pscustomobject]@{ Renewed = $false; Thumbprint = 'abc'; NotAfter = (Get-Date).AddYears(1) } }
        Mock Write-LogMessage {}
        Mock Get-CippException { @{} }
    }

    AfterEach {
        foreach ($Name in $script:SavedEnv.Keys) {
            if ($null -eq $script:SavedEnv[$Name]) { Remove-Item "env:$Name" -ErrorAction SilentlyContinue }
            else { Set-Item "env:$Name" -Value $script:SavedEnv[$Name] }
        }
    }

    It 'does NOT generate a client secret when certificate mode is on' {
        $env:CertificateAuthMode = $true

        Start-UpdateTokensTimer -Confirm:$false

        Should -Invoke New-GraphPostRequest -Times 0 -Exactly -ParameterFilter { $uri -match 'addPassword' }
    }

    It 'still generates a client secret when certificate mode is off (guard proven)' {
        Remove-Item env:CertificateAuthMode -ErrorAction SilentlyContinue

        Start-UpdateTokensTimer -Confirm:$false

        Should -Invoke New-GraphPostRequest -Times 1 -Exactly -ParameterFilter { $uri -match 'addPassword' }
    }
}
