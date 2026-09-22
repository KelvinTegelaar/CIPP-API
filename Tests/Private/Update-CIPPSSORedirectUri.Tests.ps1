# Pester tests for Update-CIPPSSORedirectUri
# Focused on the delegated-scope backfill added alongside offline_access: an app registration
# created before a scope joined the default set must have it added at warmup, additively, without
# dropping anything already declared - while an app that already has every scope costs no write.

BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
    $FunctionPath = Join-Path $RepoRoot 'Modules/CIPPCore/Public/Authentication/Update-CIPPSSORedirectUri.ps1'

    # Minimal stubs so Mock has commands to replace during tests
    function Get-CIPPTable { param($TableName) }
    function Get-CIPPAzDataTableEntity { param($Context, $Filter) }
    function Get-CippKeyVaultName { }
    function Get-CippKeyVaultSecret { param($VaultName, $Name, [switch]$AsPlainText) }
    function Get-CIPPSiteHostname { param([switch]$AsRedirectUri, [switch]$IncludeStatus, [switch]$NoFallback) }
    function New-GraphGetRequest { param($uri, $NoAuthCheck, $AsApp) }
    function New-GraphPOSTRequest { param($uri, $body, $type, $NoAuthCheck, $AsApp) }
    function Write-LogMessage { param($API, $message, $LogData, $sev) }
    function Get-CippException { param($Exception) }

    . $FunctionPath

    $script:GraphResourceId = '00000003-0000-0000-c000-000000000000'
    $script:OpenId = '37f7f235-527c-4136-accd-4a02d197296e'
    $script:ProfileScope = '14dad69e-099b-42c9-810b-d002981feec1'
    $script:Email = '64a6cdd6-aab1-4aaf-94b8-3cc8405e90d0'
    $script:OfflineAccess = '7427e0e9-2fba-42fe-b0c0-848c9e6a8182'
}

Describe 'Update-CIPPSSORedirectUri scope backfill' {
    BeforeEach {
        $script:SsoAppId = '33333333-3333-3333-3333-333333333333'
        $script:AppObjectId = 'app-object-id'
        $script:Callback = 'https://cipp.example.com/.auth/login/aad/callback'

        $script:OriginalStorage = $env:AzureWebJobsStorage
        $script:OriginalNonLocal = $env:NonLocalHostAzurite
        $script:OriginalHostname = $env:WEBSITE_HOSTNAME

        # Hosted (Key Vault) path, single tenant, URIs already correct so only scopes vary.
        $env:AzureWebJobsStorage = 'DefaultEndpointsProtocol=https;AccountName=stub'
        $env:NonLocalHostAzurite = $null
        $env:WEBSITE_HOSTNAME = 'cipp.example.com'

        # Graph resourceAccess declared on the app - each test overrides this before calling.
        $script:AppScopeIds = @($script:OpenId, $script:ProfileScope, $script:Email)
        # Any extra (non-Graph) requiredResourceAccess entries the app carries.
        $script:ExtraResources = @()

        Mock -CommandName Get-CippKeyVaultName -MockWith { 'stub-vault' }
        Mock -CommandName Get-CippKeyVaultSecret -MockWith {
            if ($Name -eq 'SSOAppId') { return $script:SsoAppId }
            if ($Name -eq 'SSOMultiTenant') { return 'False' }
            return $null
        }
        Mock -CommandName Get-CIPPSiteHostname -MockWith {
            [PSCustomObject]@{ RedirectUris = @($script:Callback); Discovered = $true; Error = $null }
        }
        Mock -CommandName Write-LogMessage -MockWith { }
        Mock -CommandName Get-CippException -MockWith { @{ NormalizedError = 'stub' } }
        Mock -CommandName New-GraphPOSTRequest -MockWith { }

        Mock -CommandName New-GraphGetRequest -MockWith {
            [PSCustomObject]@{
                id                     = $script:AppObjectId
                signInAudience         = 'AzureADMyOrg'
                web                    = [PSCustomObject]@{ redirectUris = @($script:Callback) }
                requiredResourceAccess = @(
                    @($script:ExtraResources)
                    [PSCustomObject]@{
                        resourceAppId  = $script:GraphResourceId
                        resourceAccess = @($script:AppScopeIds | ForEach-Object { [PSCustomObject]@{ id = $_; type = 'Scope' } })
                    }
                )
            }
        }
    }

    AfterEach {
        $env:AzureWebJobsStorage = $script:OriginalStorage
        $env:NonLocalHostAzurite = $script:OriginalNonLocal
        $env:WEBSITE_HOSTNAME = $script:OriginalHostname
    }

    It 'backfills offline_access when the app registration is missing it' {
        # App has only the original three scopes
        $script:AppScopeIds = @($script:OpenId, $script:ProfileScope, $script:Email)

        Update-CIPPSSORedirectUri

        Should -Invoke -CommandName New-GraphPOSTRequest -Times 1 -Exactly -ParameterFilter {
            $type -eq 'PATCH' -and
            $uri -eq "https://graph.microsoft.com/v1.0/applications/$script:AppObjectId" -and
            (($body | ConvertFrom-Json).requiredResourceAccess | Where-Object { $_.resourceAppId -eq $script:GraphResourceId }).resourceAccess.id -contains $script:OfflineAccess
        }
    }

    It 'keeps the scopes already declared when backfilling' {
        $script:AppScopeIds = @($script:OpenId, $script:ProfileScope, $script:Email)

        Update-CIPPSSORedirectUri

        Should -Invoke -CommandName New-GraphPOSTRequest -Times 1 -Exactly -ParameterFilter {
            $GraphAccess = (($body | ConvertFrom-Json).requiredResourceAccess | Where-Object { $_.resourceAppId -eq $script:GraphResourceId }).resourceAccess.id
            @($script:OpenId, $script:ProfileScope, $script:Email, $script:OfflineAccess) | ForEach-Object { $_ -in $GraphAccess } | Should -Not -Contain $false
            $true
        }
    }

    It 'writes nothing when every required scope is already declared' {
        $script:AppScopeIds = @($script:OpenId, $script:ProfileScope, $script:Email, $script:OfflineAccess)

        Update-CIPPSSORedirectUri

        Should -Invoke -CommandName New-GraphPOSTRequest -Times 0 -Exactly
    }

    It 'preserves a non-Graph resource entry while backfilling the Graph scopes' {
        $script:AppScopeIds = @($script:OpenId, $script:ProfileScope, $script:Email)
        $script:ExtraResources = @(
            [PSCustomObject]@{
                resourceAppId  = '00000002-0000-0000-c000-000000000000'
                resourceAccess = @([PSCustomObject]@{ id = 'some-other-scope-id'; type = 'Scope' })
            }
        )

        Update-CIPPSSORedirectUri

        Should -Invoke -CommandName New-GraphPOSTRequest -Times 1 -Exactly -ParameterFilter {
            $Resources = ($body | ConvertFrom-Json).requiredResourceAccess
            ($Resources | Where-Object { $_.resourceAppId -eq '00000002-0000-0000-c000-000000000000' }) -and
            (($Resources | Where-Object { $_.resourceAppId -eq $script:GraphResourceId }).resourceAccess.id -contains $script:OfflineAccess)
        }
    }
}
