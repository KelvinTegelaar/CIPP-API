# In certificate-only mode CIPP adds no client secret, so the app management policy exemption must
# NOT disable the password-addition block - doing so would re-permit secrets on the CIPP app and
# defeat the tenant's "Block password addition" (Secure Future Initiative) policy. It must still
# disable the key-credential restrictions so the SAM certificate can be registered. Both are pinned.

BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))

    function New-GraphBulkRequest { param($Requests, $NoAuthCheck, $asapp, $tenantid, $headers) }
    function New-GraphPostRequest { param($uri, $type, $body, $asapp, $NoAuthCheck, $tenantid, $headers) }

    . (Join-Path $RepoRoot 'Modules/CIPPCore/Public/GraphHelper/Update-AppManagementPolicy.ps1')
}

Describe 'Update-AppManagementPolicy certificate-only exemption' {
    BeforeEach {
        $script:CreatedPolicyBody = $null
        $script:SavedEnv = @{}
        foreach ($Name in 'CertificateAuthMode', 'ApplicationID') { $script:SavedEnv[$Name] = [Environment]::GetEnvironmentVariable($Name) }
        Remove-Item env:CertificateAuthMode -ErrorAction SilentlyContinue
        $env:ApplicationID = 'sam-app-id'

        # Default tenant policy blocks BOTH password addition and asymmetric key lifetime.
        Mock New-GraphBulkRequest {
            @(
                [pscustomobject]@{ id = 'defaultPolicy'; body = [pscustomobject]@{
                        applicationRestrictions = [pscustomobject]@{
                            passwordCredentials = @([pscustomobject]@{ restrictionType = 'passwordAddition'; state = 'enabled' })
                            keyCredentials      = @([pscustomobject]@{ restrictionType = 'asymmetricKeyLifetime'; state = 'enabled' })
                        }
                    } }
                [pscustomobject]@{ id = 'appPolicies'; body = [pscustomobject]@{ value = @() } }
                [pscustomobject]@{ id = 'appRegistration'; body = [pscustomobject]@{ id = 'cipp-obj-id'; appId = 'cipp-app-id'; displayName = 'CIPP-SAM' } }
            )
        }

        # Capture the created exemption policy body; the assignment call just needs to succeed.
        Mock New-GraphPostRequest -ParameterFilter { $uri -eq 'https://graph.microsoft.com/v1.0/policies/appManagementPolicies' } {
            $script:CreatedPolicyBody = $body | ConvertFrom-Json
            [pscustomobject]@{ id = 'new-policy-id' }
        }
        Mock New-GraphPostRequest { [pscustomobject]@{ id = 'new-policy-id' } }
    }

    AfterEach {
        foreach ($Name in $script:SavedEnv.Keys) {
            if ($null -eq $script:SavedEnv[$Name]) { Remove-Item "env:$Name" -ErrorAction SilentlyContinue }
            else { Set-Item "env:$Name" -Value $script:SavedEnv[$Name] }
        }
    }

    It 'omits the password-credential exemption in certificate-only mode (key exemption still applied)' {
        $null = Update-AppManagementPolicy -TenantFilter 'contoso' -ApplicationId 'cipp-app-id' -CertificateOnly $true

        $script:CreatedPolicyBody | Should -Not -BeNullOrEmpty
        # Password block left in force - no passwordCredentials exemption.
        $script:CreatedPolicyBody.restrictions.PSObject.Properties.Name | Should -Not -Contain 'passwordCredentials'
        # Key restrictions still disabled so the SAM certificate can be registered.
        $KeyTypes = $script:CreatedPolicyBody.restrictions.keyCredentials.restrictionType
        $KeyTypes | Should -Contain 'asymmetricKeyLifetime'
        $KeyTypes | Should -Contain 'trustedCertificateAuthority'
    }

    It 'includes the password-credential exemption in secret mode' {
        $null = Update-AppManagementPolicy -TenantFilter 'contoso' -ApplicationId 'cipp-app-id' -CertificateOnly $false

        $script:CreatedPolicyBody | Should -Not -BeNullOrEmpty
        $PwdTypes = $script:CreatedPolicyBody.restrictions.passwordCredentials.restrictionType
        $PwdTypes | Should -Contain 'passwordAddition'
        $PwdTypes | Should -Contain 'symmetricKeyAddition'
        $script:CreatedPolicyBody.restrictions.keyCredentials.restrictionType | Should -Contain 'asymmetricKeyLifetime'
    }

    It 'defaults to skipping the password exemption for the SAM app when the flag is on' {
        $env:CertificateAuthMode = $true

        $null = Update-AppManagementPolicy -TenantFilter 'contoso' -ApplicationId 'sam-app-id'

        $script:CreatedPolicyBody.restrictions.PSObject.Properties.Name | Should -Not -Contain 'passwordCredentials'
    }

    It 'still exempts the password for a NON-SAM app even when the flag is on' {
        # The global flag must not strip the password exemption from other app registrations, which
        # legitimately use a secret - only the SAM app authenticates with the certificate.
        $env:CertificateAuthMode = $true

        $null = Update-AppManagementPolicy -TenantFilter 'contoso' -ApplicationId 'some-other-app'

        $script:CreatedPolicyBody.restrictions.passwordCredentials.restrictionType | Should -Contain 'passwordAddition'
    }
}
