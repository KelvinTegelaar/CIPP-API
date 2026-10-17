BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
    . (Join-Path $RepoRoot 'Modules/CIPPCore/Public/Authentication/Get-CippProtectedAppId.ps1')

    function Get-CIPPTable { param($tablename) @{} }
    function Get-CIPPAzDataTableEntity { param($Filter) }
    function Get-CippKeyVaultName { }
    function Get-CippKeyVaultSecret { param($VaultName, $Name, [switch]$AsPlainText) }
}

Describe 'Get-CippProtectedAppId' {
    BeforeEach {
        $script:SavedEnv = @{}
        foreach ($Name in 'CIPPNG', 'WEBSITE_AUTH_V2_CONFIG_JSON', 'AzureWebJobsStorage', 'NonLocalHostAzurite', 'CIPP_SSO_MIGRATION_APPID', 'ApplicationID') {
            $script:SavedEnv[$Name] = [Environment]::GetEnvironmentVariable($Name)
            [Environment]::SetEnvironmentVariable($Name, $null)
        }
        $env:WEBSITE_AUTH_V2_CONFIG_JSON = '{"identityProviders":{"azureActiveDirectory":{"registration":{"clientId":"easyauth-app"}}}}'
        $env:ApplicationID = 'sam-app'
        Mock -CommandName Get-CippKeyVaultName -MockWith { 'kv' }
        Mock -CommandName Get-CippKeyVaultSecret -MockWith { 'stored-sso-app' }
    }

    AfterEach {
        foreach ($Name in $script:SavedEnv.Keys) { [Environment]::SetEnvironmentVariable($Name, $script:SavedEnv[$Name]) }
    }

    It 'returns the EasyAuth, stored SSO and SAM app ids on Craft' {
        $env:CIPPNG = 'true'

        @(Get-CippProtectedAppId) | Should -Be @('easyauth-app', 'stored-sso-app', 'sam-app')
    }

    It 'does not treat the EasyAuth clientId as the SSO app on classic Functions, where it is an API client' {
        @(Get-CippProtectedAppId) | Should -Be @('stored-sso-app', 'sam-app')
    }

    It 'still returns the other ids when the Key Vault read fails' {
        $env:CIPPNG = 'true'
        Mock -CommandName Get-CippKeyVaultSecret -MockWith { throw 'SecretNotFound' }

        @(Get-CippProtectedAppId) | Should -Be @('easyauth-app', 'sam-app')
    }
}
