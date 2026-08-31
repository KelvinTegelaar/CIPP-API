# Update-AppManagementPolicy builds the "CIPP Exemption Policy" body that Graph must accept. Graph
# rejects the whole appManagementPolicy create when it carries a restriction type it does not need, or
# a lifetime-type restriction (asymmetricKeyLifetime) without a valid maxLifetime. These tests pin the
# emitted body so a hardened tenant's default policy no longer blocks the exemption.

BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))

    function New-GraphBulkRequest { param($Requests, $NoAuthCheck, $asapp, $tenantid, $headers) }
    function New-GraphPostRequest { param($uri, $type, $body, $asapp, $NoAuthCheck, $tenantid, $headers) }

    . (Join-Path $RepoRoot 'Modules/CIPPCore/Public/GraphHelper/Update-AppManagementPolicy.ps1')

    $script:AppId = '981f26a1-7f43-403b-a875-f8b09b8cd720'

    # Builds the three-item bulk response the function expects, with the caller-supplied default policy
    # restrictions and an empty app-policy list (no existing exemption, app not yet targeted).
    function New-BulkResponse {
        param($PasswordRestrictions = @(), $KeyRestrictions = @())
        @(
            [PSCustomObject]@{ id = 'defaultPolicy'; body = [PSCustomObject]@{
                    applicationRestrictions = [PSCustomObject]@{
                        passwordCredentials = $PasswordRestrictions
                        keyCredentials      = $KeyRestrictions
                    }
                }
            }
            [PSCustomObject]@{ id = 'appPolicies'; body = [PSCustomObject]@{ value = @() } }
            [PSCustomObject]@{ id = 'appRegistration'; body = [PSCustomObject]@{ id = 'mfa-app-object-id'; appId = $script:AppId; displayName = 'Azure Multi-Factor Auth Client' } }
        )
    }
}

Describe 'Update-AppManagementPolicy exemption body' {
    BeforeEach {
        $script:CreateBody = $null
        $script:AssignUri = $null
        # Certificate-only mode is exercised in the sibling CertificateOnly suite; pin it off here so the
        # body-shape assertions do not depend on the host's CertificateAuthMode environment variable.
        $script:SavedCertMode = [Environment]::GetEnvironmentVariable('CertificateAuthMode')
        Remove-Item env:CertificateAuthMode -ErrorAction SilentlyContinue

        Mock New-GraphPostRequest {
            if ($uri -match 'policies/appManagementPolicies$') {
                $script:CreateBody = $body | ConvertFrom-Json
            }
            if ($uri -match 'appManagementPolicies/\$ref$') {
                $script:AssignUri = $uri
            }
            [PSCustomObject]@{ id = 'created-policy-id' }
        }
    }

    AfterEach {
        if ($null -eq $script:SavedCertMode) { Remove-Item env:CertificateAuthMode -ErrorAction SilentlyContinue }
        else { $env:CertificateAuthMode = $script:SavedCertMode }
    }

    It 'emits only the passwordCredentials block when the default policy blocks password addition' {
        Mock New-GraphBulkRequest {
            New-BulkResponse -PasswordRestrictions @([PSCustomObject]@{ restrictionType = 'passwordAddition'; state = 'enabled' })
        }

        $null = Update-AppManagementPolicy -TenantFilter 'contoso.onmicrosoft.com' -ApplicationId $script:AppId -CertificateOnly $false

        $script:CreateBody | Should -Not -BeNullOrEmpty
        $script:CreateBody.restrictions.passwordCredentials | Should -Not -BeNullOrEmpty
        # No key credentials are blocked, so the body must not drag in a keyCredentials restriction Graph would reject.
        $script:CreateBody.restrictions.PSObject.Properties.Name | Should -Not -Contain 'keyCredentials'
    }

    It 'emits an asymmetricKeyLifetime restriction with a non-null maxLifetime when key credentials are blocked' {
        Mock New-GraphBulkRequest {
            New-BulkResponse -KeyRestrictions @([PSCustomObject]@{ restrictionType = 'asymmetricKeyLifetime'; state = 'enabled'; maxLifetime = 'P90D' })
        }

        $null = Update-AppManagementPolicy -TenantFilter 'contoso.onmicrosoft.com' -ApplicationId $script:AppId -CertificateOnly $false

        $script:CreateBody | Should -Not -BeNullOrEmpty
        $Lifetime = $script:CreateBody.restrictions.keyCredentials | Where-Object { $_.restrictionType -eq 'asymmetricKeyLifetime' }
        $Lifetime | Should -Not -BeNullOrEmpty
        $Lifetime.maxLifetime | Should -Not -BeNullOrEmpty
        # It echoes the tenant default's value when the default exposes one.
        $Lifetime.maxLifetime | Should -Be 'P90D'
    }

    It 'falls back to a conservative maxLifetime when the default policy does not expose one' {
        Mock New-GraphBulkRequest {
            New-BulkResponse -KeyRestrictions @([PSCustomObject]@{ restrictionType = 'asymmetricKeyLifetime'; state = 'enabled' })
        }

        $null = Update-AppManagementPolicy -TenantFilter 'contoso.onmicrosoft.com' -ApplicationId $script:AppId -CertificateOnly $false

        $Lifetime = $script:CreateBody.restrictions.keyCredentials | Where-Object { $_.restrictionType -eq 'asymmetricKeyLifetime' }
        $Lifetime.maxLifetime | Should -Be 'P730D'
    }

    It 'assigns the exemption to the application registration by default' {
        Mock New-GraphBulkRequest {
            New-BulkResponse -PasswordRestrictions @([PSCustomObject]@{ restrictionType = 'passwordAddition'; state = 'enabled' })
        }

        $null = Update-AppManagementPolicy -TenantFilter 'contoso.onmicrosoft.com' -ApplicationId $script:AppId -CertificateOnly $false

        $script:AssignUri | Should -Not -BeNullOrEmpty
        $script:AssignUri | Should -Match '/applications/'
        $script:AssignUri | Should -Not -Match '/servicePrincipals/'
    }

    It 'assigns the exemption to the service principal when -ServicePrincipal is set' {
        Mock New-GraphBulkRequest {
            New-BulkResponse -PasswordRestrictions @([PSCustomObject]@{ restrictionType = 'passwordAddition'; state = 'enabled' })
        }

        $null = Update-AppManagementPolicy -TenantFilter 'contoso.onmicrosoft.com' -ApplicationId $script:AppId -CertificateOnly $false -ServicePrincipal

        $script:AssignUri | Should -Not -BeNullOrEmpty
        $script:AssignUri | Should -Match '/servicePrincipals/'
        $script:AssignUri | Should -Not -Match '/applications/'
    }

    It 'treats an already-assigned policy reference as success, not a failure' {
        Mock New-GraphBulkRequest {
            New-BulkResponse -PasswordRestrictions @([PSCustomObject]@{ restrictionType = 'passwordAddition'; state = 'enabled' })
        }
        # The target already has the policy assigned, so the $ref POST returns a duplicate-reference error.
        Mock New-GraphPostRequest -ParameterFilter { $uri -match 'appManagementPolicies/\$ref$' } {
            throw "One or more added object references already exist for the following modified properties: 'appManagementPolicies'."
        }

        # A throw here would surface as a test error, which is the failure we are guarding against.
        $result = Update-AppManagementPolicy -TenantFilter 'contoso.onmicrosoft.com' -ApplicationId $script:AppId -CertificateOnly $false -ServicePrincipal
        $result.PolicyAction | Should -Not -Match 'Failed'
        $result.PolicyAction | Should -Match 'assigned'
    }
}
