# New-CIPPMFAConnectorToken caches a long-lived connector secret per tenant so the expensive provisioning
# (adding a credential to the MFA client SP) only runs when no usable cached secret exists. These tests pin
# that a cached secret is reused without provisioning, and that a cache miss provisions and stores one.

BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))

    function New-GraphGetRequest { param($uri, $tenantid, $AsApp) }
    function New-GraphPostRequest { param($uri, $tenantid, $type, $body, $AsApp) }
    function Update-AppManagementPolicy { param($TenantFilter, $ApplicationId, [switch]$ServicePrincipal) }
    function Get-CIPPTable { param($tablename) }
    function Get-CIPPAzDataTableEntity { param($Filter) }
    function Add-CIPPAzDataTableEntity { param($Entity, [switch]$Force) }
    function Get-Tenants { param($TenantFilter) }

    . (Join-Path $RepoRoot 'Modules/CIPPCore/Public/GraphHelper/New-CIPPMFAConnectorToken.ps1')

    $script:TenantGuid = '11111111-1111-1111-1111-111111111111'
    $script:MFAAppID = '981f26a1-7f43-403b-a875-f8b09b8cd720'
}

Describe 'New-CIPPMFAConnectorToken secret caching' {
    BeforeEach {
        # Force the dev (DevSecrets table) storage path so the assertions are deterministic.
        $env:NonLocalHostAzurite = 'true'
        Mock Get-CIPPTable { @{ Context = 'stub' } }
        Mock Add-CIPPAzDataTableEntity {}
        Mock Update-AppManagementPolicy {}
        # Token exchange
        Mock Invoke-RestMethod { [pscustomobject]@{ access_token = 'TOKEN123' } }
        # SP lookup returns the MFA client SP so provisioning finds it (no SP create)
        Mock New-GraphGetRequest { @([pscustomobject]@{ id = 'mfa-sp-id'; appId = $script:MFAAppID }) }
        # addPassword returns a fresh secret
        Mock New-GraphPostRequest { [pscustomobject]@{ secretText = 'NEWSECRET' } }
    }

    AfterEach {
        Remove-Item env:NonLocalHostAzurite -ErrorAction SilentlyContinue
    }

    It 'reuses a cached secret without provisioning' {
        Mock Get-CIPPAzDataTableEntity { [pscustomobject]@{ SecretValue = 'CACHEDSECRET' } }

        $result = New-CIPPMFAConnectorToken -TenantFilter $script:TenantGuid

        $result.AccessToken | Should -Be 'TOKEN123'
        # No provisioning: neither the SP lookup nor addPassword should run on a cache hit.
        Should -Not -Invoke New-GraphGetRequest
        Should -Not -Invoke New-GraphPostRequest
        Should -Not -Invoke Add-CIPPAzDataTableEntity
    }

    It 'provisions and stores a new secret on a cache miss' {
        Mock Get-CIPPAzDataTableEntity { $null }

        $result = New-CIPPMFAConnectorToken -TenantFilter $script:TenantGuid

        $result.AccessToken | Should -Be 'TOKEN123'
        # addPassword is the only New-GraphPostRequest here (the SP already exists), and the new secret is cached.
        Should -Invoke New-GraphPostRequest -Times 1 -Exactly
        Should -Invoke Add-CIPPAzDataTableEntity -Times 1 -Exactly
    }
}
