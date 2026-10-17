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
    function Add-CIPPAzDataTableEntity { param($Context, $Entity, [switch]$Force) }
    function Get-CippKeyVaultName {}
    function Get-CippKeyVaultSecret { param($VaultName, $Name, [switch]$AsPlainText) }
    function Set-CippKeyVaultSecret { param($VaultName, $Name, $SecretValue) }
    function Get-CIPPSAMCredentials {}
    function Compare-CIPPSAMCredentialSnapshot { param($Acknowledge, $AcknowledgeNote, $CredentialState) }
    function Set-CIPPSAMCredentialRecord { param($KeyId, $Source, $Label, $Headers) }
    function Add-CIPPSSOAppSecret { param($ObjectId, $AppId) }
    function Set-CIPPSSOStoredCredentials { param($AppSecret) }

    . (Join-Path $RepoRoot 'Modules/CIPPCore/Public/Entrypoints/Timer Functions/Start-UpdateTokensTimer.ps1')
    . (Join-Path $RepoRoot 'Modules/CIPPCore/Public/Authentication/Update-CIPPSAMSecret.ps1')
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
        Mock Add-CIPPAzDataTableEntity {}
        Mock Get-CIPPSAMCredentials { [pscustomobject]@{ Credentials = @() } }
        Mock Compare-CIPPSAMCredentialSnapshot {}
        Mock Set-CIPPSAMCredentialRecord { 'CIPP' }
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

Describe 'Start-UpdateTokensTimer tracked secret expiry' {
    BeforeEach {
        $script:SavedEnv = @{}
        foreach ($Name in 'CertificateAuthMode', 'ApplicationID', 'TenantID', 'AzureWebJobsStorage') { $script:SavedEnv[$Name] = [Environment]::GetEnvironmentVariable($Name) }
        Remove-Item env:CertificateAuthMode -ErrorAction SilentlyContinue
        $env:ApplicationID = 'sam-app-id'
        $env:TenantID = '11111111-2222-3333-4444-555555555555'
        $env:AzureWebJobsStorage = 'UseDevelopmentStorage=true'

        Mock Get-GraphToken { @{ Refresh_token = 'refresh-token' } }
        Mock Get-CIPPTable { @{} }
        Mock Get-Tenants { @() }
        Mock Add-AzDataTableEntity {}
        Mock Add-CIPPAzDataTableEntity {}
        # This instance's secret expires in 10 days; another CIPP instance's secret on the same app runs for a year.
        Mock Get-CIPPAzDataTableEntity -ParameterFilter { $Filter -match 'AppCache' } { [pscustomobject]@{ ApplicationId = 'sam-app-id'; SecretKeyId = 'ours' } }
        Mock Get-CIPPAzDataTableEntity -ParameterFilter { $Filter -match "RowKey eq 'Secret'" } { [pscustomobject]@{ PartitionKey = 'Secret'; RowKey = 'Secret'; RefreshToken = '' } }
        Mock Get-CIPPAzDataTableEntity { $null }
        Mock New-GraphGetRequest {
            [pscustomobject]@{
                id                                = 'app-obj-id'
                passwordCredentials               = @(
                    [pscustomobject]@{ keyId = 'ours'; displayName = 'UpdateTokens'; endDateTime = (Get-Date).AddDays(10).ToUniversalTime() }
                    [pscustomobject]@{ keyId = 'theirs'; displayName = 'UpdateTokens'; endDateTime = (Get-Date).AddDays(365).ToUniversalTime() }
                )
                servicePrincipalLockConfiguration = [pscustomobject]@{ isEnabled = $true }
            }
        }
        Mock New-GraphPostRequest { [pscustomobject]@{ secretText = 's'; keyId = 'new'; endDateTime = (Get-Date).AddYears(1) } }
        Mock Update-AppManagementPolicy { [pscustomobject]@{ PolicyAction = 'none' } }
        Mock Update-CIPPSAMCertificate { [pscustomobject]@{ Renewed = $false } }
        Mock Write-LogMessage {}
        Mock Get-CippException { @{} }
        Mock Get-CIPPSAMCredentials { [pscustomobject]@{ Credentials = @() } }
        Mock Compare-CIPPSAMCredentialSnapshot {}
        Mock Set-CIPPSAMCredentialRecord { 'CIPP' }
    }

    AfterEach {
        foreach ($Name in $script:SavedEnv.Keys) {
            if ($null -eq $script:SavedEnv[$Name]) { Remove-Item "env:$Name" -ErrorAction SilentlyContinue }
            else { Set-Item "env:$Name" -Value $script:SavedEnv[$Name] }
        }
    }

    It 'rotates when the tracked secret expires soon even though a newer secret exists' {
        Start-UpdateTokensTimer -Confirm:$false

        Should -Invoke New-GraphPostRequest -Times 1 -Exactly -ParameterFilter { $uri -match 'addPassword' }
        Should -Invoke Add-CIPPAzDataTableEntity -Times 1 -Exactly -ParameterFilter { $Entity.SecretKeyId -eq 'new' }
    }

    It 'falls back to the newest secret when the tracked keyId is gone from the app' {
        Mock Get-CIPPAzDataTableEntity -ParameterFilter { $Filter -match 'AppCache' } { [pscustomobject]@{ ApplicationId = 'sam-app-id'; SecretKeyId = 'deleted' } }

        Start-UpdateTokensTimer -Confirm:$false

        Should -Invoke New-GraphPostRequest -Times 0 -Exactly -ParameterFilter { $uri -match 'addPassword' }
    }
}
