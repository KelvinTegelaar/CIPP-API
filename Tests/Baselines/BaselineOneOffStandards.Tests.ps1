# One-off standard conversions (backlog batch 1). Each test pins a normalization or grading
# decision that fails SILENTLY if it regresses - the standard reports Compliant (or permanent
# Drift) and nobody notices.

BeforeAll {
    $script:RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
    $Baselines = Join-Path $script:RepoRoot 'Modules/CIPPCore/Public/Baselines'

    function New-CIPPDbRequest { param($TenantFilter, $Type) }
    function Write-LogMessage { param($API, $tenant, $message, $Sev, $LogData) }
    function Get-CIPPDbItem { param($TenantFilter, $Type, [switch]$CountsOnly) }
    function New-GraphGetRequest { param($uri, $tenantid, $AsApp) }
    function New-GraphPostRequest { param($uri, $tenantid, $type, $body, $AsApp) }
    function New-TeamsRequestV2 { param($TenantFilter, $Type, $Action, $Identity, $Parameters, [switch]$NoRead) }
    function New-ExoRequest { param($tenantid, $cmdlet, $cmdParams, $useSystemMailbox) }

    . (Join-Path $script:RepoRoot 'Modules/CIPPCore/Public/Get-CIPPIntuneCompareExclusions.ps1')
    . (Join-Path $script:RepoRoot 'Modules/CIPPCore/Public/Compare-CIPPIntuneObject.ps1')
    . (Join-Path $Baselines 'Get-CIPPBaselineCacheRows.ps1')
    . (Join-Path $Baselines 'Test-CIPPBaselineCacheCollected.ps1')
    foreach ($Name in @('ExternalMFATrusted', 'IntuneDeviceRetirementDays', 'AppManagementPolicy', 'EnableAppConsentRequests', 'TeamsFederationConfiguration', 'OMEBranding')) {
        . (Join-Path $Baselines "Get-CIPPBaseline${Name}State.ps1")
        . (Join-Path $Baselines "Invoke-CIPPBaseline${Name}.ps1")
    }

    $script:Tenant = 'contoso.onmicrosoft.com'
    function ConvertTo-Cached { param([Parameter(ValueFromPipeline = $true)]$InputObject) process { $InputObject | ConvertTo-Json -Depth 20 | ConvertFrom-Json } }
    function Get-Verdict {
        param($Expected, $Current)
        $Projected = [PSCustomObject]@{}
        foreach ($Key in $Expected.PSObject.Properties.Name) { $Projected | Add-Member -NotePropertyName $Key -NotePropertyValue $Current.$Key }
        @(Compare-CIPPIntuneObject -ReferenceObject $Expected -DifferenceObject $Projected | Where-Object { $_ })
    }
}

Describe 'Get-CIPPBaselineExternalMFATrustedState' {
    It 'grades the trust switch in BOTH directions' {
        # Deliberately NOT trusting external MFA is a valid posture; a one-way grade would
        # report a trusting tenant compliant against a distrusting baseline.
        Mock New-CIPPDbRequest { @(@{ inboundTrust = @{ isMfaAccepted = $true } } | ConvertTo-Cached) }
        $Off = [PSCustomObject]@{ Variables = [PSCustomObject]@{ state = $false } }
        $Prepared = Get-CIPPBaselineExternalMFATrustedState -Item $Off -TenantFilter $script:Tenant
        (Get-Verdict -Expected $Prepared.Expected -Current $Prepared.Current).Count | Should -BeGreaterThan 0
        $On = [PSCustomObject]@{ Variables = [PSCustomObject]@{ state = $true } }
        $Prepared2 = Get-CIPPBaselineExternalMFATrustedState -Item $On -TenantFilter $script:Tenant
        (Get-Verdict -Expected $Prepared2.Expected -Current $Prepared2.Current).Count | Should -Be 0
    }

    It 'patches the MERGED inboundTrust, never the lone flag' {
        # Graph PATCH replaces the whole complex value - a bare isMfaAccepted body silently
        # resets the device-trust flags beside it.
        Mock New-GraphGetRequest { [PSCustomObject]@{ inboundTrust = [PSCustomObject]@{ isMfaAccepted = $false; isCompliantDeviceAccepted = $true; isHybridAzureADJoinedDeviceAccepted = $true } } }
        Mock New-GraphPostRequest { }
        Invoke-CIPPBaselineExternalMFATrusted -Remediate ([PSCustomObject]@{ trusted = $true }) -TenantFilter $script:Tenant -Current $null
        Should -Invoke New-GraphPostRequest -Times 1 -Exactly -ParameterFilter {
            $type -eq 'PATCH' -and $body -match '"isMfaAccepted":\s*true' -and $body -match 'isCompliantDeviceAccepted'
        }
    }
}

Describe 'Get-CIPPBaselineIntuneDeviceRetirementDaysState' {
    BeforeAll { $script:DaysItem = [PSCustomObject]@{ Variables = [PSCustomObject]@{ days = 90 } } }
    BeforeEach { Mock Get-CIPPDbItem { [PSCustomObject]@{ RowKey = 'ManagedDeviceCleanupRules-Count'; DataCount = 1 } } }

    It 'prefers the all-platforms rule over platform-scoped rules' {
        Mock New-CIPPDbRequest { @(
                (@{ id = 'r-ios'; deviceCleanupRulePlatformType = 'ios'; deviceInactivityBeforeRetirementInDays = 30 } | ConvertTo-Cached),
                (@{ id = 'r-all'; deviceCleanupRulePlatformType = 'all'; deviceInactivityBeforeRetirementInDays = 90 } | ConvertTo-Cached)
            ) }
        $Prepared = Get-CIPPBaselineIntuneDeviceRetirementDaysState -Item $script:DaysItem -TenantFilter $script:Tenant
        $Prepared.Current.ruleId | Should -Be 'r-all'
        (Get-Verdict -Expected $Prepared.Expected -Current $Prepared.Current).Count | Should -Be 0
    }

    It 'grades a tenant with no cleanup rule as drift, not No Data' {
        Mock New-CIPPDbRequest { @() }
        Mock Get-CIPPDbItem { [PSCustomObject]@{ RowKey = 'ManagedDeviceCleanupRules-Count'; DataCount = 0 } }
        $Prepared = Get-CIPPBaselineIntuneDeviceRetirementDaysState -Item $script:DaysItem -TenantFilter $script:Tenant
        $Prepared.Current | Should -Not -BeNullOrEmpty
        $Prepared.Current.ruleId | Should -BeNullOrEmpty
        (Get-Verdict -Expected $Prepared.Expected -Current $Prepared.Current).Count | Should -BeGreaterThan 0
    }

    It 'creates when no rule exists and patches the existing rule otherwise' {
        Mock New-GraphPostRequest { }
        Invoke-CIPPBaselineIntuneDeviceRetirementDays -Remediate ([PSCustomObject]@{ days = 90 }) -TenantFilter $script:Tenant -Current ([PSCustomObject]@{ ruleId = $null })
        Should -Invoke New-GraphPostRequest -Times 1 -Exactly -ParameterFilter { $type -eq 'POST' }
        Invoke-CIPPBaselineIntuneDeviceRetirementDays -Remediate ([PSCustomObject]@{ days = 90 }) -TenantFilter $script:Tenant -Current ([PSCustomObject]@{ ruleId = 'r-all' })
        Should -Invoke New-GraphPostRequest -Times 1 -Exactly -ParameterFilter { $type -eq 'PATCH' -and $uri -match "r-all" }
    }
}

Describe 'Get-CIPPBaselineAppManagementPolicyState' {
    BeforeAll {
        $script:AmpItem = [PSCustomObject]@{ Variables = [PSCustomObject]@{ passwordCredentialsPasswordAddition = 'enabled'; passwordCredentialsCustomPasswordAddition = ''; passwordCredentialsMaxLifetime = ''; keyCredentialsMaxLifetime = '' } }
    }

    It 'mirrors password addition onto symmetric key addition, like the classic' {
        Mock New-CIPPDbRequest { @(@{ isEnabled = $true; applicationRestrictions = @{ passwordCredentials = @(); keyCredentials = @() }; servicePrincipalRestrictions = @{ passwordCredentials = @(); keyCredentials = @() } } | ConvertTo-Cached) }
        $Prepared = Get-CIPPBaselineAppManagementPolicyState -Item $script:AmpItem -TenantFilter $script:Tenant
        @($Prepared.Expected.applicationRestrictions.passwordCredentials).restrictionType | Should -Contain 'symmetricKeyAddition'
        @($Prepared.Expected.servicePrincipalRestrictions.passwordCredentials).restrictionType | Should -Contain 'passwordAddition'
    }

    It 'converts day counts to ISO durations' {
        Mock New-CIPPDbRequest { @(@{ isEnabled = $true; applicationRestrictions = @{ passwordCredentials = @(); keyCredentials = @() }; servicePrincipalRestrictions = @{ passwordCredentials = @(); keyCredentials = @() } } | ConvertTo-Cached) }
        $Item = [PSCustomObject]@{ Variables = [PSCustomObject]@{ passwordCredentialsMaxLifetime = 30; keyCredentialsMaxLifetime = 365 } }
        $Prepared = Get-CIPPBaselineAppManagementPolicyState -Item $Item -TenantFilter $script:Tenant
        (@($Prepared.Expected.applicationRestrictions.passwordCredentials) | Where-Object { $_.restrictionType -eq 'passwordLifetime' }).maxLifetime | Should -Be 'P30D'
        (@($Prepared.Expected.applicationRestrictions.keyCredentials) | Where-Object { $_.restrictionType -eq 'asymmetricKeyLifetime' }).maxLifetime | Should -Be 'P365D'
    }

    It 'reports No Data when nothing is configured, expressing no opinion' {
        $Empty = [PSCustomObject]@{ Variables = [PSCustomObject]@{} }
        (Get-CIPPBaselineAppManagementPolicyState -Item $Empty -TenantFilter $script:Tenant).Current | Should -BeNullOrEmpty
    }
}

Describe 'Get-CIPPBaselineEnableAppConsentRequestsState' {
    It 'tolerates reviewers an operator added by hand' {
        # The merge write preserves extra reviewers, so grading them (as the classic''s
        # count compare did) would be permanent unfixable drift.
        Mock New-CIPPDbRequest { @(@{ isEnabled = $true; reviewers = @(
                    @{ query = "/beta/roleManagement/directory/roleAssignments?`$filter=roleDefinitionId eq '62e90394-69f5-4237-9190-012177145e10'" },
                    @{ query = '/v1.0/users/hand-added-reviewer@contoso.com' }
                ) } | ConvertTo-Cached) }
        $Item = [PSCustomObject]@{ Variables = [PSCustomObject]@{} }
        $Prepared = Get-CIPPBaselineEnableAppConsentRequestsState -Item $Item -TenantFilter $script:Tenant
        @($Prepared.Current.missingReviewerRoles).Count | Should -Be 0
        (Get-Verdict -Expected $Prepared.Expected -Current $Prepared.Current).Count | Should -Be 0
    }

    It 'reports drift when the configured role is not among the reviewers' {
        Mock New-CIPPDbRequest { @(@{ isEnabled = $true; reviewers = @(@{ query = '/v1.0/users/someone@contoso.com' }) } | ConvertTo-Cached) }
        $Item = [PSCustomObject]@{ Variables = [PSCustomObject]@{ ReviewerRoles = [PSCustomObject]@{ label = 'GA'; value = '62e90394-69f5-4237-9190-012177145e10' } } }
        $Prepared = Get-CIPPBaselineEnableAppConsentRequestsState -Item $Item -TenantFilter $script:Tenant
        $Prepared.Current.missingReviewerRoles | Should -Contain '62e90394-69f5-4237-9190-012177145e10'
    }

    It 'merges configured roles into the reviewer list without dropping hand-added ones' {
        Mock New-GraphGetRequest { @{ isEnabled = $false; notifyReviewers = $false; remindersEnabled = $false; requestDurationInDays = 0; reviewers = @(@{ query = '/v1.0/users/keepme@contoso.com'; queryType = 'MicrosoftGraph'; queryRoot = 'null' }) } | ConvertTo-Cached }
        Mock New-GraphPostRequest { }
        Invoke-CIPPBaselineEnableAppConsentRequests -Remediate ([PSCustomObject]@{ reviewerRoles = @() }) -TenantFilter $script:Tenant -Current $null
        Should -Invoke New-GraphPostRequest -Times 1 -Exactly -ParameterFilter {
            $type -eq 'PUT' -and $body -match 'keepme@contoso.com' -and $body -match '62e90394-69f5-4237-9190-012177145e10' -and $body -match '"isEnabled":\s*true'
        }
    }

    It 'grades configured reviewer users by display name, not mail' {
        # displayName is the match key on purpose: a guest's mail can land in mail,
        # otherMails or nowhere depending on how the account was created.
        Mock New-CIPPDbRequest {
            if ($Type -eq 'Users') {
                @(@{ id = '11111111-aaaa-bbbb-cccc-222222222222'; displayName = 'MSP Support'; userPrincipalName = 'support_msp.com#EXT#@contoso.onmicrosoft.com' } | ConvertTo-Cached)
            } else {
                @(@{ isEnabled = $true; reviewers = @(
                            @{ query = "/beta/roleManagement/directory/roleAssignments?`$filter=roleDefinitionId eq '62e90394-69f5-4237-9190-012177145e10'" },
                            @{ query = '/users/11111111-aaaa-bbbb-cccc-222222222222' }
                        ) } | ConvertTo-Cached)
            }
        }
        $Item = [PSCustomObject]@{ Variables = [PSCustomObject]@{ ReviewerUsers = @([PSCustomObject]@{ label = 'MSP Support'; value = 'MSP Support' }) } }
        $Prepared = Get-CIPPBaselineEnableAppConsentRequestsState -Item $Item -TenantFilter $script:Tenant
        @($Prepared.Current.missingReviewerUsers).Count | Should -Be 0
        (Get-Verdict -Expected $Prepared.Expected -Current $Prepared.Current).Count | Should -Be 0
    }

    It 'reports drift when the configured user is absent from the reviewers or does not exist' {
        Mock New-CIPPDbRequest {
            if ($Type -eq 'Users') {
                @(@{ id = '11111111-aaaa-bbbb-cccc-222222222222'; displayName = 'MSP Support'; userPrincipalName = 'support_msp.com#EXT#@contoso.onmicrosoft.com' } | ConvertTo-Cached)
            } else {
                @(@{ isEnabled = $true; reviewers = @() } | ConvertTo-Cached)
            }
        }
        $Item = [PSCustomObject]@{ Variables = [PSCustomObject]@{ ReviewerUsers = @('MSP Support', 'Ghost Account') } }
        $Prepared = Get-CIPPBaselineEnableAppConsentRequestsState -Item $Item -TenantFilter $script:Tenant
        $Prepared.Current.missingReviewerUsers | Should -Contain 'MSP Support'
        # A name that resolves to no user at all is missing too - the reviewer account
        # the operator expects does not exist in the tenant.
        $Prepared.Current.missingReviewerUsers | Should -Contain 'Ghost Account'
    }

    It 'resolves reviewer users by display name and does not duplicate one already present' {
        Mock New-GraphGetRequest {
            if ($uri -match '/users\?') {
                @(@{ id = '33333333-dddd-eeee-ffff-444444444444'; displayName = 'MSP Support' } | ConvertTo-Cached)
            } else {
                @{ isEnabled = $false; notifyReviewers = $false; remindersEnabled = $false; requestDurationInDays = 0; reviewers = @(@{ query = '/users/33333333-dddd-eeee-ffff-444444444444'; queryType = 'MicrosoftGraph'; queryRoot = 'null' }) } | ConvertTo-Cached
            }
        }
        Mock New-GraphPostRequest { }
        Invoke-CIPPBaselineEnableAppConsentRequests -Remediate ([PSCustomObject]@{ reviewerRoles = @(); reviewerUsers = @('MSP Support') }) -TenantFilter $script:Tenant -Current $null
        Should -Invoke New-GraphPostRequest -Times 1 -Exactly -ParameterFilter {
            $type -eq 'PUT' -and ([regex]::Matches($body, '33333333-dddd-eeee-ffff-444444444444')).Count -eq 1 -and $body -match '62e90394-69f5-4237-9190-012177145e10'
        }
    }
}

Describe 'Get-CIPPBaselineTeamsFederationConfigurationState' {
    BeforeEach {
        Mock Get-CIPPDbItem { [PSCustomObject]@{ RowKey = 'CsTenantFederationConfiguration-Count'; DataCount = 1 } }
    }

    It 'reads the GET shape: allow-all is an AllowedDomains object with no member list' {
        Mock New-CIPPDbRequest { @(@{ AllowTeamsConsumer = $false; AllowTeamsConsumerInbound = $false; AllowFederatedUsers = $true; AllowedDomains = @{}; BlockedDomains = @() } | ConvertTo-Cached) }
        $Item = [PSCustomObject]@{ Variables = [PSCustomObject]@{ DomainControl = 'AllowAllExternal'; AllowTeamsConsumer = $false; AllowTeamsConsumerInbound = $false } }
        $Prepared = Get-CIPPBaselineTeamsFederationConfigurationState -Item $Item -TenantFilter $script:Tenant
        $Prepared.Current.allowedDomains | Should -Be 'AllowAllKnownDomains'
        (Get-Verdict -Expected $Prepared.Expected -Current $Prepared.Current).Count | Should -Be 0
    }

    It 'unwraps {Domain} objects and sorts before comparing specific allow lists' {
        Mock New-CIPPDbRequest { @(@{ AllowTeamsConsumer = $false; AllowTeamsConsumerInbound = $false; AllowFederatedUsers = $true; AllowedDomains = @{ AllowedDomain = @(@{ Domain = 'b.com' }, @{ Domain = 'a.com' }) }; BlockedDomains = @() } | ConvertTo-Cached) }
        $Item = [PSCustomObject]@{ Variables = [PSCustomObject]@{ DomainControl = 'AllowSpecificExternal'; DomainList = 'a.com, b.com'; AllowTeamsConsumer = $false; AllowTeamsConsumerInbound = $false } }
        $Prepared = Get-CIPPBaselineTeamsFederationConfigurationState -Item $Item -TenantFilter $script:Tenant
        (Get-Verdict -Expected $Prepared.Expected -Current $Prepared.Current).Count | Should -Be 0
    }

    It 'a SINGLE allowed domain still grades as an ARRAY - the if-expression unwrap made it a scalar' {
        # One domain drifted forever with visually identical want/got: expected array vs
        # current scalar after the assignment unwrapped the one-element pipeline.
        Mock New-CIPPDbRequest { @(@{ AllowTeamsConsumer = $false; AllowTeamsConsumerInbound = $false; AllowFederatedUsers = $true; AllowedDomains = @{ AllowedDomain = @(@{ Domain = 'googe.com' }) }; BlockedDomains = @() } | ConvertTo-Cached) }
        $Item = [PSCustomObject]@{ Variables = [PSCustomObject]@{ DomainControl = 'AllowSpecificExternal'; DomainList = 'googe.com'; AllowTeamsConsumer = $false; AllowTeamsConsumerInbound = $false } }
        $Prepared = Get-CIPPBaselineTeamsFederationConfigurationState -Item $Item -TenantFilter $script:Tenant
        ($Prepared.Current.allowedDomains -is [array]) | Should -BeTrue
        (Get-Verdict -Expected $Prepared.Expected -Current $Prepared.Current).Count | Should -Be 0
    }

    It 'ignores both domain lists in BlockAllExternal mode, like the classic' {
        Mock New-CIPPDbRequest { @(@{ AllowTeamsConsumer = $false; AllowTeamsConsumerInbound = $false; AllowFederatedUsers = $false; AllowedDomains = @{ AllowedDomain = @('stale.com') }; BlockedDomains = @('old.com') } | ConvertTo-Cached) }
        $Item = [PSCustomObject]@{ Variables = [PSCustomObject]@{ DomainControl = 'BlockAllExternal'; AllowTeamsConsumer = $false; AllowTeamsConsumerInbound = $false } }
        $Prepared = Get-CIPPBaselineTeamsFederationConfigurationState -Item $Item -TenantFilter $script:Tenant
        (Get-Verdict -Expected $Prepared.Expected -Current $Prepared.Current).Count | Should -Be 0
    }

    It 'writes through the ConfigAPI with the carried PUT-shaped payload' {
        Mock New-TeamsRequestV2 { }
        $Current = [PSCustomObject]@{ writePayload = [PSCustomObject]@{ AllowTeamsConsumer = $false; AllowTeamsConsumerInbound = $false; AllowFederatedUsers = $true; AllowedDomains = @{ AllowList = @('a.com') }; BlockedDomains = @() } }
        Invoke-CIPPBaselineTeamsFederationConfiguration -Remediate $null -TenantFilter $script:Tenant -Current $Current
        Should -Invoke New-TeamsRequestV2 -Times 1 -Exactly -ParameterFilter {
            $Action -eq 'Set' -and $NoRead -eq $true -and $Parameters.AllowedDomains.AllowList -contains 'a.com'
        }
    }
}

Describe 'Get-CIPPBaselineOMEBrandingState' {
    BeforeAll {
        $script:OmeConfig = @{ Identity = 'OME Configuration'; BackgroundColor = '#ffffff'; EmailText = 'Secure mail'; IntroductionText = ''; ReadButtonText = ''; PortalText = ''; DisclaimerText = ''; PrivacyStatementUrl = ''; OTPEnabled = $true; SocialIdSignIn = $false }
    }
    BeforeEach { Mock Get-CIPPDbItem { [PSCustomObject]@{ RowKey = 'ExoOMEConfiguration-Count'; DataCount = 1 } } }

    It 'grades only the fields the baseline configures' {
        Mock New-CIPPDbRequest { @($script:OmeConfig | ConvertTo-Cached) }
        $Item = [PSCustomObject]@{ Variables = [PSCustomObject]@{ BackgroundColor = '#ffffff' } }
        $Prepared = Get-CIPPBaselineOMEBrandingState -Item $Item -TenantFilter $script:Tenant
        $Prepared.Expected.PSObject.Properties.Name | Should -Be @('BackgroundColor')
        (Get-Verdict -Expected $Prepared.Expected -Current $Prepared.Current).Count | Should -Be 0
    }

    It 'reports drift on a configured field that differs' {
        Mock New-CIPPDbRequest { @($script:OmeConfig | ConvertTo-Cached) }
        $Item = [PSCustomObject]@{ Variables = [PSCustomObject]@{ BackgroundColor = '#000000' } }
        $Prepared = Get-CIPPBaselineOMEBrandingState -Item $Item -TenantFilter $script:Tenant
        (Get-Verdict -Expected $Prepared.Expected -Current $Prepared.Current).Count | Should -BeGreaterThan 0
    }

    It 'grades a configured logo as permanent drift, the classic behaviour made visible' {
        Mock New-CIPPDbRequest { @($script:OmeConfig | ConvertTo-Cached) }
        $Item = [PSCustomObject]@{ Variables = [PSCustomObject]@{ LogoUrl = 'https://example.com/logo.png' } }
        $Prepared = Get-CIPPBaselineOMEBrandingState -Item $Item -TenantFilter $script:Tenant
        $Prepared.Current.logoApplied | Should -BeFalse
        (Get-Verdict -Expected $Prepared.Expected -Current $Prepared.Current).Count | Should -BeGreaterThan 0
    }

    It 'reports No Data when no branding field is configured' {
        Mock New-CIPPDbRequest { @($script:OmeConfig | ConvertTo-Cached) }
        $Item = [PSCustomObject]@{ Variables = [PSCustomObject]@{} }
        (Get-CIPPBaselineOMEBrandingState -Item $Item -TenantFilter $script:Tenant).Current | Should -BeNullOrEmpty
    }

    It 'writes only configured fields and survives a failed logo download' {
        Mock New-ExoRequest { }
        Mock Invoke-WebRequest { throw 'download failed' }
        Mock Write-LogMessage { }
        $Remediate = [PSCustomObject]@{ backgroundColor = '#000000'; logoUrl = 'https://example.com/logo.png' }
        Invoke-CIPPBaselineOMEBranding -Remediate $Remediate -TenantFilter $script:Tenant -Current ([PSCustomObject]@{ omeIdentity = 'OME Configuration' })
        Should -Invoke New-ExoRequest -Times 1 -Exactly -ParameterFilter {
            $cmdlet -eq 'Set-OMEConfiguration' -and $cmdParams.BackgroundColor -eq '#000000' -and -not $cmdParams.ContainsKey('Image') -and -not $cmdParams.ContainsKey('EmailText')
        }
    }
}
