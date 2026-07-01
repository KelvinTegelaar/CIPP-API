# Pester tests for Set-CIPPAuthenticationPolicy
# Validates that method-specific sub-settings are written to the Graph PATCH body

BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
    $FunctionPath = Join-Path $RepoRoot 'Modules/CIPPCore/Public/Set-CIPPAuthenticationPolicy.ps1'

    # Mock returns whatever the current test stored, simulating the existing Graph config
    function New-GraphGetRequest { param($Uri, $tenantid, $AsApp) return $script:mockCurrentInfo }
    function New-GraphPostRequest {
        param($tenantid, $Uri, $Type, $Body, $ContentType, $AsApp)
        $script:lastBody = $Body
    }
    function Write-LogMessage { param($headers, $API, $tenant, $message, $sev, $LogData) }
    function Get-CippException { param($Exception) $Exception }

    . $FunctionPath
}

Describe 'Set-CIPPAuthenticationPolicy' {
    BeforeEach {
        $script:lastBody = $null
        $script:mockCurrentInfo = $null
    }

    It 'writes Temporary Access Pass sub-settings to the PATCH body' {
        $script:mockCurrentInfo = [pscustomobject]@{
            state                    = 'disabled'
            isUsableOnce             = $true
            minimumLifetimeInMinutes = 10
            maximumLifetimeInMinutes = 20
            defaultLifetimeInMinutes = 15
            defaultLength            = 8
        }

        Set-CIPPAuthenticationPolicy -Tenant 'contoso.onmicrosoft.com' -AuthenticationMethodId 'TemporaryAccessPass' `
            -Enabled $true -TAPisUsableOnce $false -TAPDefaultLength 12 -TAPDefaultLifeTime 90

        $body = $script:lastBody | ConvertFrom-Json
        $body.state | Should -Be 'enabled'
        $body.isUsableOnce | Should -Be $false
        $body.defaultLength | Should -Be 12
        $body.defaultLifetimeInMinutes | Should -Be 90
    }

    It 'honors the FIDO2 attestation/self-service parameters instead of forcing true' {
        $script:mockCurrentInfo = [pscustomobject]@{
            state                            = 'disabled'
            isAttestationEnforced            = $true
            isSelfServiceRegistrationAllowed = $true
        }

        Set-CIPPAuthenticationPolicy -Tenant 'contoso.onmicrosoft.com' -AuthenticationMethodId 'FIDO2' `
            -Enabled $true -FIDO2AttestationEnforced $false -FIDO2SelfServiceRegistration $false

        $body = $script:lastBody | ConvertFrom-Json
        $body.isAttestationEnforced | Should -Be $false
        $body.isSelfServiceRegistrationAllowed | Should -Be $false
    }

    It 'defaults FIDO2 to enforced/allowed when no parameters are passed' {
        $script:mockCurrentInfo = [pscustomobject]@{
            state                            = 'disabled'
            isAttestationEnforced            = $false
            isSelfServiceRegistrationAllowed = $false
        }

        Set-CIPPAuthenticationPolicy -Tenant 'contoso.onmicrosoft.com' -AuthenticationMethodId 'FIDO2' -Enabled $true

        $body = $script:lastBody | ConvertFrom-Json
        $body.isAttestationEnforced | Should -Be $true
        $body.isSelfServiceRegistrationAllowed | Should -Be $true
    }

    It 'scopes the method to all users when GroupIds contains all_users' {
        $script:mockCurrentInfo = [pscustomobject]@{
            state          = 'disabled'
            includeTargets = @()
        }

        Set-CIPPAuthenticationPolicy -Tenant 'contoso.onmicrosoft.com' -AuthenticationMethodId 'softwareOath' `
            -Enabled $true -GroupIds @('all_users')

        $body = $script:lastBody | ConvertFrom-Json
        $body.includeTargets[0].targetType | Should -Be 'group'
        $body.includeTargets[0].id | Should -Be 'all_users'
    }

    It 'stamps SMS isUsableForSignIn onto every include-target' {
        $script:mockCurrentInfo = [pscustomobject]@{
            state          = 'disabled'
            includeTargets = @(
                [pscustomobject]@{ targetType = 'group'; id = 'all_users' }
            )
        }

        Set-CIPPAuthenticationPolicy -Tenant 'contoso.onmicrosoft.com' -AuthenticationMethodId 'SMS' `
            -Enabled $true -SmsIsUsableForSignIn $true

        $body = $script:lastBody | ConvertFrom-Json
        $body.includeTargets[0].isUsableForSignIn | Should -Be $true
    }

    It 'clears Email exclude targets when an empty group list is supplied' {
        $script:mockCurrentInfo = [pscustomobject]@{
            state          = 'disabled'
            excludeTargets = @([pscustomobject]@{ targetType = 'group'; id = 'old-group' })
        }

        Set-CIPPAuthenticationPolicy -Tenant 'contoso.onmicrosoft.com' -AuthenticationMethodId 'Email' `
            -Enabled $true -EmailExcludeGroupIds @()

        $body = $script:lastBody | ConvertFrom-Json
        @($body.excludeTargets).Count | Should -Be 0
    }

    It 'writes the Voice isOfficePhoneAllowed setting to the PATCH body' {
        $script:mockCurrentInfo = [pscustomobject]@{
            state               = 'disabled'
            isOfficePhoneAllowed = $false
        }

        Set-CIPPAuthenticationPolicy -Tenant 'contoso.onmicrosoft.com' -AuthenticationMethodId 'Voice' `
            -Enabled $true -VoiceIsOfficePhoneAllowed $true

        $body = $script:lastBody | ConvertFrom-Json
        $body.isOfficePhoneAllowed | Should -Be $true
    }
}
