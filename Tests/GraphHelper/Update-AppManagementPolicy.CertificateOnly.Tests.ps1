# In certificate-only mode the CIPP exemption policy must itself BLOCK adding secrets to the SAM app,
# whatever the tenant default says, so the app can only authenticate with the certificate. It must
# still disable the key-credential restrictions so the SAM certificate can be registered. Secret mode
# lifts the block again so CIPP can rotate its own secret. All three are pinned.

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
        foreach ($Name in 'CertificateAuthMode', 'ApplicationID', 'TenantID') { $script:SavedEnv[$Name] = [Environment]::GetEnvironmentVariable($Name) }
        Remove-Item env:CertificateAuthMode, env:TenantID -ErrorAction SilentlyContinue
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

    It 'blocks password addition on the app in certificate-only mode (key exemption still applied)' {
        $null = Update-AppManagementPolicy -TenantFilter 'contoso' -ApplicationId 'cipp-app-id' -CertificateOnly $true

        $script:CreatedPolicyBody | Should -Not -BeNullOrEmpty
        $Pwd = $script:CreatedPolicyBody.restrictions.passwordCredentials
        ($Pwd | Where-Object { $_.restrictionType -eq 'passwordAddition' }).state | Should -Be 'enabled'
        ($Pwd | Where-Object { $_.restrictionType -eq 'symmetricKeyAddition' }).state | Should -Be 'enabled'
        # Key restrictions still disabled so the SAM certificate can be registered.
        $KeyTypes = $script:CreatedPolicyBody.restrictions.keyCredentials.restrictionType
        $KeyTypes | Should -Contain 'asymmetricKeyLifetime'
        $KeyTypes | Should -Contain 'trustedCertificateAuthority'
    }

    It 'creates the secret block in certificate-only mode even when the tenant default restricts nothing' {
        Mock New-GraphBulkRequest {
            @(
                [pscustomobject]@{ id = 'defaultPolicy'; body = [pscustomobject]@{ applicationRestrictions = [pscustomobject]@{ passwordCredentials = @(); keyCredentials = @() } } }
                [pscustomobject]@{ id = 'appPolicies'; body = [pscustomobject]@{ value = @() } }
                [pscustomobject]@{ id = 'appRegistration'; body = [pscustomobject]@{ id = 'cipp-obj-id'; appId = 'cipp-app-id'; displayName = 'CIPP-SAM' } }
            )
        }

        $null = Update-AppManagementPolicy -TenantFilter 'contoso' -ApplicationId 'cipp-app-id' -CertificateOnly $true

        $script:CreatedPolicyBody | Should -Not -BeNullOrEmpty
        ($script:CreatedPolicyBody.restrictions.passwordCredentials | Where-Object { $_.restrictionType -eq 'passwordAddition' }).state | Should -Be 'enabled'
        $script:CreatedPolicyBody.restrictions.PSObject.Properties.Name | Should -Not -Contain 'keyCredentials'
    }

    It 'lifts an existing secret block when switching back to secret mode' {
        $script:PatchedPolicyBody = $null
        Mock New-GraphBulkRequest -ParameterFilter { $Requests[0].url -like '*/appliesTo' } {
            @([pscustomobject]@{ id = 'cipp-policy-id'; body = [pscustomobject]@{ value = @([pscustomobject]@{ appId = 'cipp-app-id' }) } })
        }
        Mock New-GraphBulkRequest -ParameterFilter { $Requests[0].id -eq 'defaultPolicy' } {
            @(
                [pscustomobject]@{ id = 'defaultPolicy'; body = [pscustomobject]@{ applicationRestrictions = [pscustomobject]@{ passwordCredentials = @(); keyCredentials = @() } } }
                [pscustomobject]@{ id = 'appPolicies'; body = [pscustomobject]@{ value = @([pscustomobject]@{
                                id = 'cipp-policy-id'; displayName = 'CIPP Exemption Policy'; isEnabled = $true
                                restrictions = [pscustomobject]@{ passwordCredentials = @([pscustomobject]@{ restrictionType = 'passwordAddition'; state = 'enabled' }, [pscustomobject]@{ restrictionType = 'symmetricKeyAddition'; state = 'enabled' }) }
                            }) } }
                [pscustomobject]@{ id = 'appRegistration'; body = [pscustomobject]@{ id = 'cipp-obj-id'; appId = 'cipp-app-id'; displayName = 'CIPP-SAM' } }
            )
        }
        Mock New-GraphPostRequest -ParameterFilter { $type -eq 'PATCH' -and $uri -like '*/appManagementPolicies/cipp-policy-id' } {
            $script:PatchedPolicyBody = $body | ConvertFrom-Json
        }

        $Result = Update-AppManagementPolicy -TenantFilter 'contoso' -ApplicationId 'cipp-app-id' -CertificateOnly $false

        $script:PatchedPolicyBody | Should -Not -BeNullOrEmpty
        ($script:PatchedPolicyBody.restrictions.passwordCredentials | Where-Object { $_.restrictionType -eq 'passwordAddition' }).state | Should -Be 'disabled'
        $Result.PolicyAction | Should -Be 'Updated existing policy cipp-policy-id to allow credentials'
    }

    It 'includes the password-credential exemption in secret mode' {
        $null = Update-AppManagementPolicy -TenantFilter 'contoso' -ApplicationId 'cipp-app-id' -CertificateOnly $false

        $script:CreatedPolicyBody | Should -Not -BeNullOrEmpty
        $PwdTypes = $script:CreatedPolicyBody.restrictions.passwordCredentials.restrictionType
        $PwdTypes | Should -Contain 'passwordAddition'
        $PwdTypes | Should -Contain 'symmetricKeyAddition'
        $script:CreatedPolicyBody.restrictions.keyCredentials.restrictionType | Should -Contain 'asymmetricKeyLifetime'
    }

    It 'defaults to blocking secrets for the SAM app when the flag is on' {
        $env:CertificateAuthMode = $true

        $null = Update-AppManagementPolicy -TenantFilter 'contoso' -ApplicationId 'sam-app-id'

        ($script:CreatedPolicyBody.restrictions.passwordCredentials | Where-Object { $_.restrictionType -eq 'passwordAddition' }).state | Should -Be 'enabled'
    }

    It 'still exempts the password for a NON-SAM app even when the flag is on' {
        # The global flag must not strip the password exemption from other app registrations, which
        # legitimately use a secret - only the SAM app authenticates with the certificate.
        $env:CertificateAuthMode = $true

        $null = Update-AppManagementPolicy -TenantFilter 'contoso' -ApplicationId 'some-other-app'

        $script:CreatedPolicyBody.restrictions.passwordCredentials.restrictionType | Should -Contain 'passwordAddition'
    }

    It 'moves a secret-based app off the certificate-only SAM policy instead of rewriting it' {
        # SSO/API apps once shared 'CIPP Exemption Policy'; exempting them rewrote the SAM policy to allow
        # secrets, silently undoing certificate-only mode. They must get their own policy and leave SAM's alone.
        $env:CertificateAuthMode = $true
        $script:SamPolicyPatched = $false
        $script:Unassigned = $false
        Mock New-GraphBulkRequest -ParameterFilter { $Requests[0].url -like '*/appliesTo' } {
            @([pscustomobject]@{ id = 'cipp-policy-id'; body = [pscustomobject]@{ value = @([pscustomobject]@{ appId = 'sso-app-id' }) } })
        }
        Mock New-GraphBulkRequest -ParameterFilter { $Requests[0].id -eq 'defaultPolicy' } {
            @(
                [pscustomobject]@{ id = 'defaultPolicy'; body = [pscustomobject]@{ applicationRestrictions = [pscustomobject]@{ passwordCredentials = @(); keyCredentials = @() } } }
                [pscustomobject]@{ id = 'appPolicies'; body = [pscustomobject]@{ value = @([pscustomobject]@{
                                id = 'cipp-policy-id'; displayName = 'CIPP Exemption Policy'; isEnabled = $true
                                restrictions = [pscustomobject]@{ passwordCredentials = @([pscustomobject]@{ restrictionType = 'passwordAddition'; state = 'enabled' }, [pscustomobject]@{ restrictionType = 'symmetricKeyAddition'; state = 'enabled' }) }
                            }) } }
                [pscustomobject]@{ id = 'appRegistration'; body = [pscustomobject]@{ id = 'sso-obj-id'; appId = 'sso-app-id'; displayName = 'CIPP-SSO' } }
            )
        }
        Mock New-GraphPostRequest -ParameterFilter { $type -eq 'PATCH' -and $uri -like '*/appManagementPolicies/cipp-policy-id' } { $script:SamPolicyPatched = $true }
        Mock New-GraphPostRequest -ParameterFilter { $type -eq 'DELETE' -and $uri -like '*/sso-obj-id/appManagementPolicies/cipp-policy-id/$ref' } { $script:Unassigned = $true }

        $null = Update-AppManagementPolicy -TenantFilter 'contoso' -ApplicationId 'sso-app-id' -PolicyName 'CIPP SSO and API Exemption Policy'

        $script:SamPolicyPatched | Should -BeFalse
        $script:Unassigned | Should -BeTrue
        $script:CreatedPolicyBody.displayName | Should -Be 'CIPP SSO and API Exemption Policy'
        ($script:CreatedPolicyBody.restrictions.passwordCredentials | Where-Object { $_.restrictionType -eq 'passwordAddition' }).state | Should -Be 'disabled'
    }

    It 'every non-SAM caller passes its own -PolicyName' {
        # Static guard: a caller relying on the default name would reuse (and rewrite) the CIPP-SAM policy.
        $NonSamCallers = @(
            'Modules/CIPPCore/Public/Authentication/New-CIPPSSOApp.ps1'
            'Modules/CIPPCore/Public/Authentication/Add-CIPPSSOAppSecret.ps1'
            'Modules/CIPPCore/Public/Authentication/New-CIPPAPIConfig.ps1'
            'Modules/CIPPCore/Public/GraphHelper/New-CIPPMFAConnectorToken.ps1'
        )
        foreach ($File in $NonSamCallers) {
            $Calls = Select-String -Path (Join-Path $RepoRoot $File) -Pattern '^\s*\$\w+ = Update-AppManagementPolicy ' | ForEach-Object { $_.Line }
            $Calls | Should -Not -BeNullOrEmpty -Because "$File should call Update-AppManagementPolicy"
            foreach ($Call in $Calls) { $Call | Should -Match '-PolicyName ' -Because "$File must not reuse the CIPP-SAM policy" }
        }
    }

    It 'never creates a policy for the SAM app in a customer tenant' {
        $SavedTenant = $env:TenantID
        $env:TenantID = 'partner-tenant-id'
        try {
            $Result = Update-AppManagementPolicy -TenantFilter 'customer-tenant-id' -ApplicationId 'sam-app-id' -CertificateOnly $true

            Should -Invoke New-GraphBulkRequest -Times 0 -Exactly
            Should -Invoke New-GraphPostRequest -Times 0 -Exactly
            $Result.PolicyAction | Should -BeLike 'Skipped*partner tenant*'
        } finally {
            if ($null -eq $SavedTenant) { Remove-Item env:TenantID -ErrorAction SilentlyContinue } else { $env:TenantID = $SavedTenant }
        }
    }
}
