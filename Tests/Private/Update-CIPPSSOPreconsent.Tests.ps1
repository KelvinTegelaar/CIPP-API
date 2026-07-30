# Pester tests for Update-CIPPSSOPreconsent
# Verifies the CIPP-SSO app gets a tenant-wide (AllPrincipals) Graph consent grant during warmup,
# that an already-granted app costs no Graph calls, and that every failure path is soft - warmup
# must never be broken by a tenant that refuses the grant.

BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
    $FunctionPath = Join-Path $RepoRoot 'Modules/CIPPCore/Public/Authentication/Update-CIPPSSOPreconsent.ps1'

    # Minimal stubs so Mock has commands to replace during tests
    function Get-CIPPTable { param($TableName) }
    function Get-CIPPAzDataTableEntity { param($Context, $Filter) }
    function Add-CIPPAzDataTableEntity { param($Context, $Entity, [switch]$Force) }
    function Get-CippKeyVaultName { }
    function Get-CippKeyVaultSecret { param($VaultName, $Name, [switch]$AsPlainText) }
    function New-GraphGetRequest { param($uri, $NoAuthCheck, $AsApp) }
    function New-GraphPOSTRequest { param($uri, $body, $type, $NoAuthCheck, $AsApp) }
    function Write-LogMessage { param($API, $message, $LogData, $sev) }
    function Get-CippException { param($Exception) }

    . $FunctionPath
}

Describe 'Update-CIPPSSOPreconsent' {
    BeforeEach {
        $script:SsoAppId = '22222222-2222-2222-2222-222222222222'
        $script:SsoSpId = 'sp-sso-object-id'
        $script:GraphSpId = 'sp-graph-object-id'
        $script:GraphAppId = '00000003-0000-0000-c000-000000000000'

        $script:OriginalStorage = $env:AzureWebJobsStorage
        $script:OriginalNonLocal = $env:NonLocalHostAzurite
        $script:OriginalAuthEnabled = $env:WEBSITE_AUTH_ENABLED

        # Hosted (Key Vault) path by default
        $env:AzureWebJobsStorage = 'DefaultEndpointsProtocol=https;AccountName=stub'
        $env:NonLocalHostAzurite = $null

        $script:SavedEntity = $null

        Mock -CommandName Get-CIPPTable -MockWith { @{ Context = 'stub-table' } }
        Mock -CommandName Get-CippKeyVaultName -MockWith { 'stub-vault' }
        Mock -CommandName Get-CippKeyVaultSecret -MockWith { $script:SsoAppId }
        Mock -CommandName Write-LogMessage -MockWith { }
        Mock -CommandName Get-CippException -MockWith { @{ NormalizedError = 'stub' } }
        Mock -CommandName Add-CIPPAzDataTableEntity -MockWith { $script:SavedEntity = $Entity }
        Mock -CommandName New-GraphPOSTRequest -MockWith { }

        # No pre-existing migration row unless a test sets one
        Mock -CommandName Get-CIPPAzDataTableEntity -MockWith { $null }

        Mock -CommandName New-GraphGetRequest -MockWith {
            if ($uri -match [regex]::Escape("appId='$script:SsoAppId'")) { return [PSCustomObject]@{ id = $script:SsoSpId } }
            if ($uri -match [regex]::Escape("appId='$script:GraphAppId'")) { return [PSCustomObject]@{ id = $script:GraphSpId } }
            return @()
        }
    }

    AfterEach {
        $env:AzureWebJobsStorage = $script:OriginalStorage
        $env:NonLocalHostAzurite = $script:OriginalNonLocal
        $env:WEBSITE_AUTH_ENABLED = $script:OriginalAuthEnabled
    }

    Context 'When no SSO app is provisioned' {
        It 'returns without touching Graph' {
            Mock -CommandName Get-CippKeyVaultSecret -MockWith { $null }

            Update-CIPPSSOPreconsent

            Should -Invoke -CommandName New-GraphGetRequest -Times 0 -Exactly
            Should -Invoke -CommandName New-GraphPOSTRequest -Times 0 -Exactly
        }
    }

    Context 'When consent has already been granted for this app' {
        It 'skips Graph entirely' {
            Mock -CommandName Get-CIPPAzDataTableEntity -MockWith {
                [PSCustomObject]@{ Preconsented = 'true'; PreconsentedAppId = $script:SsoAppId; Status = 'complete' }
            }

            Update-CIPPSSOPreconsent

            Should -Invoke -CommandName New-GraphGetRequest -Times 0 -Exactly
        }

        It 'still runs when the stored grant belongs to a previous app registration' {
            Mock -CommandName Get-CIPPAzDataTableEntity -MockWith {
                [PSCustomObject]@{ Preconsented = 'true'; PreconsentedAppId = 'an-older-app-id'; Status = 'complete' }
            }

            Update-CIPPSSOPreconsent

            Should -Invoke -CommandName New-GraphPOSTRequest -Times 1 -Exactly
        }
    }

    Context 'When no grant exists yet' {
        It 'creates an AllPrincipals grant for the OIDC scopes' {
            Update-CIPPSSOPreconsent

            Should -Invoke -CommandName New-GraphPOSTRequest -Times 1 -Exactly -ParameterFilter {
                $type -eq 'POST' -and
                $uri -eq 'https://graph.microsoft.com/v1.0/oauth2PermissionGrants' -and
                ($body | ConvertFrom-Json).consentType -eq 'AllPrincipals' -and
                ($body | ConvertFrom-Json).clientId -eq $script:SsoSpId -and
                ($body | ConvertFrom-Json).resourceId -eq $script:GraphSpId -and
                ($body | ConvertFrom-Json).scope -eq 'openid profile email'
            }
        }

        It 'records Preconsented true against the app id' {
            Update-CIPPSSOPreconsent

            $script:SavedEntity.Preconsented | Should -Be 'true'
            $script:SavedEntity.PreconsentedAppId | Should -Be $script:SsoAppId
        }

        It 'stamps a Status on a row that has none so the settings page still reads as provisioned' {
            $env:WEBSITE_AUTH_ENABLED = 'True'

            Update-CIPPSSOPreconsent

            $script:SavedEntity.Status | Should -Be 'complete'
            $script:SavedEntity.AppId | Should -Be $script:SsoAppId
        }

        It 'leaves an existing Status untouched' {
            Mock -CommandName Get-CIPPAzDataTableEntity -MockWith {
                [PSCustomObject]@{ AppId = $script:SsoAppId; Status = 'secrets_stored' }
            }

            Update-CIPPSSOPreconsent

            $script:SavedEntity.Status | Should -Be 'secrets_stored'
        }
    }

    Context 'When a grant already exists' {
        It 'does nothing when it already covers every required scope' {
            Mock -CommandName New-GraphGetRequest -MockWith {
                if ($uri -match [regex]::Escape("appId='$script:SsoAppId'")) { return [PSCustomObject]@{ id = $script:SsoSpId } }
                if ($uri -match [regex]::Escape("appId='$script:GraphAppId'")) { return [PSCustomObject]@{ id = $script:GraphSpId } }
                return @([PSCustomObject]@{
                        id          = 'grant-1'
                        resourceId  = $script:GraphSpId
                        consentType = 'AllPrincipals'
                        scope       = 'email openid profile User.Read'
                    })
            }

            Update-CIPPSSOPreconsent

            Should -Invoke -CommandName New-GraphPOSTRequest -Times 0 -Exactly
            $script:SavedEntity.Preconsented | Should -Be 'true'
        }

        It 'patches in missing scopes without dropping the ones already consented' {
            Mock -CommandName New-GraphGetRequest -MockWith {
                if ($uri -match [regex]::Escape("appId='$script:SsoAppId'")) { return [PSCustomObject]@{ id = $script:SsoSpId } }
                if ($uri -match [regex]::Escape("appId='$script:GraphAppId'")) { return [PSCustomObject]@{ id = $script:GraphSpId } }
                return @([PSCustomObject]@{
                        id          = 'grant-1'
                        resourceId  = $script:GraphSpId
                        consentType = 'AllPrincipals'
                        scope       = 'openid User.Read'
                    })
            }

            Update-CIPPSSOPreconsent

            Should -Invoke -CommandName New-GraphPOSTRequest -Times 1 -Exactly -ParameterFilter {
                $type -eq 'PATCH' -and
                $uri -eq 'https://graph.microsoft.com/v1.0/oauth2PermissionGrants/grant-1' -and
                ($body | ConvertFrom-Json).scope -eq 'email openid profile User.Read'
            }
        }

        It 'ignores per-user grants and creates the tenant-wide one' {
            Mock -CommandName New-GraphGetRequest -MockWith {
                if ($uri -match [regex]::Escape("appId='$script:SsoAppId'")) { return [PSCustomObject]@{ id = $script:SsoSpId } }
                if ($uri -match [regex]::Escape("appId='$script:GraphAppId'")) { return [PSCustomObject]@{ id = $script:GraphSpId } }
                return @([PSCustomObject]@{
                        id          = 'grant-user'
                        resourceId  = $script:GraphSpId
                        consentType = 'Principal'
                        scope       = 'openid profile email'
                    })
            }

            Update-CIPPSSOPreconsent

            Should -Invoke -CommandName New-GraphPOSTRequest -Times 1 -Exactly -ParameterFilter { $type -eq 'POST' }
        }
    }

    Context 'When the tenant refuses the grant' {
        It 'does not throw and records Preconsented false with the reason' {
            Mock -CommandName New-GraphPOSTRequest -MockWith { throw 'Insufficient privileges to complete the operation.' }

            { Update-CIPPSSOPreconsent } | Should -Not -Throw

            $script:SavedEntity.Preconsented | Should -Be 'false'
            $script:SavedEntity.PreconsentError | Should -Match 'Insufficient privileges'
        }
    }

    Context 'When the service principal has not propagated yet' {
        It 'returns quietly without recording a failure' {
            Mock -CommandName New-GraphGetRequest -MockWith {
                if ($uri -match [regex]::Escape("appId='$script:SsoAppId'")) { throw 'Resource not found.' }
                return @()
            }

            { Update-CIPPSSOPreconsent } | Should -Not -Throw

            Should -Invoke -CommandName Add-CIPPAzDataTableEntity -Times 0 -Exactly
        }
    }
}
