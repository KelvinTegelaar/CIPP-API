# Batch 3b: the Entra heavies. These tests pin the targeting semantics that fail silently -
# keep-current versus all_users, unconfigured-method skips, default-profile-only grading, and
# additive include management.

BeforeAll {
    $script:RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
    $Baselines = Join-Path $script:RepoRoot 'Modules/CIPPCore/Public/Baselines'

    function New-CIPPDbRequest { param($TenantFilter, $Type) }
    function Write-LogMessage { param($API, $tenant, $message, $Sev, $LogData) }
    function Get-CIPPDbItem { param($TenantFilter, $Type, [switch]$CountsOnly) }
    function New-GraphGetRequest { param($uri, $tenantid, $AsApp) }
    function New-GraphPostRequest { param($uri, $tenantid, $type, $body, $AsApp, $ContentType, $scope) }
    function Set-CIPPRegistrationCampaign { param($Tenant, $State, $TargetedAuthenticationMethod, $SnoozeDurationInDays, $EnforceRegistrationAfterAllowedSnoozes, $IncludeTargets, $ExcludeTargets, $APIName) }
    function Set-CIPPAuthenticationPolicy { param($Tenant, $APIName, $AuthenticationMethodId, [bool]$Enabled, $GroupIds, $MicrosoftAuthenticatorSoftwareOathEnabled, $MicrosoftAuthenticatorDisplayAppInfo, $MicrosoftAuthenticatorDisplayLocation, $MicrosoftAuthenticatorCompanionApp, $TAPisUsableOnce, $TAPDefaultLifeTime, $TAPMinimumLifetime, $TAPMaximumLifetime, $TAPDefaultLength, $QRCodeLifetimeInDays, $QRCodePinLength, $EmailAllowExternalIdToUseEmailOtp, $EmailExcludeGroupIds) }

    . (Join-Path $script:RepoRoot 'Modules/CIPPCore/Public/Get-CIPPIntuneCompareExclusions.ps1')
    . (Join-Path $script:RepoRoot 'Modules/CIPPCore/Public/Compare-CIPPIntuneObject.ps1')
    . (Join-Path $Baselines 'Get-CIPPBaselineCacheRows.ps1')
    . (Join-Path $Baselines 'Test-CIPPBaselineCacheCollected.ps1')
    foreach ($Name in @('FIDO2PasskeyProfiles', 'CopilotLimitedMode', 'NudgeMFA', 'OauthConsent', 'DisableSelfServiceLicenses', 'AuthenticationMethods')) {
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
    Mock Get-CIPPDbItem { [PSCustomObject]@{ RowKey = 'X-Count'; DataCount = 1 } }
}

Describe 'Get-CIPPBaselineNudgeMFAState' {
    BeforeAll {
        $script:Campaign = @{ registrationEnforcement = @{ authenticationMethodsRegistrationCampaign = @{
                    state = 'enabled'; snoozeDurationInDays = 1; enforceRegistrationAfterAllowedSnoozes = $true
                    includeTargets = @(@{ id = 'g-existing'; targetType = 'group'; targetedAuthenticationMethod = 'microsoftAuthenticator' })
                    excludeTargets = @()
                } } }
    }

    It 'keeps the tenant''s current targets when the include field is blank - never resets to all_users' {
        # NudgeMFA predates the targeting fields; grading blank as all_users would flag
        # every portal-targeted deployment as drift and remediation would flatten it.
        Mock New-CIPPDbRequest { @($script:Campaign | ConvertTo-Cached) }
        $Item = [PSCustomObject]@{ Variables = [PSCustomObject]@{ state = 'enabled'; snoozeDurationInDays = 1; enforceRegistrationAfterAllowedSnoozes = $true } }
        $Prepared = Get-CIPPBaselineNudgeMFAState -Item $Item -TenantFilter $script:Tenant
        $Prepared.Expected.includeTargetIds | Should -Be @('g-existing')
        (Get-Verdict -Expected $Prepared.Expected -Current $Prepared.Current).Count | Should -Be 0
        $Prepared.Current.campaignParams.IncludeTargets | Should -BeNullOrEmpty
    }

    It 'the literal AllUsers entry targets everyone explicitly' {
        Mock New-CIPPDbRequest {
            if ($Type -eq 'AuthenticationMethodsPolicy') { @($script:Campaign | ConvertTo-Cached) } else { @() }
        }
        $Item = [PSCustomObject]@{ Variables = [PSCustomObject]@{ state = 'enabled'; snoozeDurationInDays = 1; enforceRegistrationAfterAllowedSnoozes = $true; includeTargets = 'AllUsers' } }
        $Prepared = Get-CIPPBaselineNudgeMFAState -Item $Item -TenantFilter $script:Tenant
        $Prepared.Expected.includeTargetIds | Should -Be @('all_users')
        (Get-Verdict -Expected $Prepared.Expected -Current $Prepared.Current).Count | Should -BeGreaterThan 0
    }

    It 'reports No Data when a configured group entry resolves to nothing' {
        Mock New-CIPPDbRequest {
            if ($Type -eq 'AuthenticationMethodsPolicy') { @($script:Campaign | ConvertTo-Cached) } else { @(@{ id = 'g1'; displayName = 'Some Other Group' } | ConvertTo-Cached) }
        }
        $Item = [PSCustomObject]@{ Variables = [PSCustomObject]@{ state = 'enabled'; snoozeDurationInDays = 1; enforceRegistrationAfterAllowedSnoozes = $true; includeTargets = 'Nonexistent Group' } }
        (Get-CIPPBaselineNudgeMFAState -Item $Item -TenantFilter $script:Tenant).Current | Should -BeNullOrEmpty
    }
}

Describe 'Get-CIPPBaselineAuthenticationMethodsState' {
    BeforeAll {
        $script:AuthPolicy = @{ authenticationMethodConfigurations = @(
                @{ id = 'MicrosoftAuthenticator'; state = 'enabled'; isSoftwareOathEnabled = $false; includeTargets = @(@{ id = 'all_users'; targetType = 'group' }); featureSettings = @{} }
                @{ id = 'Sms'; state = 'enabled'; includeTargets = @(@{ id = 'all_users'; targetType = 'group' }) }
            ) }
    }

    It 'grades ONLY the methods the baseline configures - unmanaged methods are invisible' {
        # SMS is enabled in the tenant but unconfigured in the baseline: grading it would
        # invent an opinion the operator never expressed.
        Mock New-CIPPDbRequest { @($script:AuthPolicy | ConvertTo-Cached) }
        $Item = [PSCustomObject]@{ Variables = [PSCustomObject]@{ MicrosoftAuthenticatorEnabled = $true } }
        $Prepared = Get-CIPPBaselineAuthenticationMethodsState -Item $Item -TenantFilter $script:Tenant
        @($Prepared.Current.methodsOutOfPolicy).Count | Should -Be 0
        (Get-Verdict -Expected $Prepared.Expected -Current $Prepared.Current).Count | Should -Be 0
    }

    It 'a drifted method contributes named drifts AND a remediation parameter set' {
        Mock New-CIPPDbRequest { @($script:AuthPolicy | ConvertTo-Cached) }
        $Item = [PSCustomObject]@{ Variables = [PSCustomObject]@{ SMSEnabled = $false } }
        $Prepared = Get-CIPPBaselineAuthenticationMethodsState -Item $Item -TenantFilter $script:Tenant
        $Prepared.Current.methodsOutOfPolicy | Should -Match 'SMS'
        @($Prepared.Current.remediationSets).Count | Should -Be 1
        $Prepared.Current.remediationSets[0].Params.AuthenticationMethodId | Should -Be 'SMS'
        $Prepared.Current.remediationSets[0].Params.Enabled | Should -BeFalse
    }

    It 'writes each drifted method through the shared policy helper, compliant ones untouched' {
        Mock Set-CIPPAuthenticationPolicy { }
        $Current = [PSCustomObject]@{ remediationSets = @([PSCustomObject]@{ Label = 'SMS'; Params = @{ AuthenticationMethodId = 'SMS'; Enabled = $false } }) }
        Invoke-CIPPBaselineAuthenticationMethods -Remediate $null -TenantFilter $script:Tenant -Current $Current
        Should -Invoke Set-CIPPAuthenticationPolicy -Times 1 -Exactly -ParameterFilter { $AuthenticationMethodId -eq 'SMS' -and $Enabled -eq $false }
    }
}

Describe 'Get-CIPPBaselineFIDO2PasskeyProfilesState' {
    BeforeAll {
        # The OPERATOR profile is deliberately first: a hook that grabs the first profile
        # instead of resolving defaultPasskeyProfile grades the wrong object and fails here.
        $script:Fido2 = @{ defaultPasskeyProfile = 'p-default'; passkeyProfiles = @(
                @{ id = 'p-other'; name = 'Operator profile'; passkeyTypes = 'synced'; attestationEnforcement = 'disabled'; keyRestrictions = @{ isEnforced = $true; enforcementType = 'allow'; aaGuids = @('guid-1') } }
                @{ id = 'p-default'; name = 'Default'; passkeyTypes = 'deviceBound'; attestationEnforcement = 'registrationOnly'; keyRestrictions = @{ isEnforced = $false; enforcementType = 'block'; aaGuids = @() } }
            ) }
    }

    It 'grades the DEFAULT profile only - operator profiles are never graded' {
        # The operator profile (p-other) differs on every field; only the default profile
        # participates. Note enforcementType grades even while restrictions are off - the
        # classic graded the dormant field, and Graph defaults it to 'block'.
        Mock New-CIPPDbRequest { @($script:Fido2 | ConvertTo-Cached) }
        $Item = [PSCustomObject]@{ Variables = [PSCustomObject]@{ PasskeyTypes = 'deviceBound'; AttestationEnforcement = 'registrationOnly'; EnforceKeyRestrictions = $false; EnforcementType = 'block' } }
        $Prepared = Get-CIPPBaselineFIDO2PasskeyProfilesState -Item $Item -TenantFilter $script:Tenant
        (Get-Verdict -Expected $Prepared.Expected -Current $Prepared.Current).Count | Should -Be 0
    }

    It 'refuses key restrictions with no AAGUIDs - allow mode would lock every authenticator out' {
        Mock New-CIPPDbRequest { @($script:Fido2 | ConvertTo-Cached) }
        $Item = [PSCustomObject]@{ Variables = [PSCustomObject]@{ PasskeyTypes = 'deviceBound'; AttestationEnforcement = 'registrationOnly'; EnforceKeyRestrictions = $true } }
        (Get-CIPPBaselineFIDO2PasskeyProfilesState -Item $Item -TenantFilter $script:Tenant).Current | Should -BeNullOrEmpty
    }

    It 'rewrites the default profile while resending every other profile untouched' {
        Mock New-GraphPostRequest { }
        $Current = [PSCustomObject]@{
            defaultProfileId = 'p-default'
            allProfiles      = @($script:Fido2.passkeyProfiles | ConvertTo-Cached)
        }
        Invoke-CIPPBaselineFIDO2PasskeyProfiles -Remediate ([PSCustomObject]@{ passkeyTypes = 'deviceBound'; attestationEnforcement = 'registrationOnly'; enforceKeyRestrictions = $false }) -TenantFilter $script:Tenant -Current $Current
        Should -Invoke New-GraphPostRequest -Times 1 -Exactly -ParameterFilter {
            $type -eq 'PATCH' -and $AsApp -eq $true -and $body -match 'p-other' -and $body -match 'guid-1'
        }
    }
}

Describe 'Get-CIPPBaselineOauthConsentState' {
    It 'grades additively: includes an operator added are never drift' {
        Mock New-CIPPDbRequest { @(@{ permissionGrantPolicyIdsAssignedToDefaultUserRole = @('ManagePermissionGrantsForSelf.cipp-consent-policy') } | ConvertTo-Cached) }
        Mock New-GraphGetRequest { @(
                (@{ permissionType = 'delegated'; clientApplicationIds = @('00b41c95-dab0-4487-9791-b9d2c32c80f2') } | ConvertTo-Cached),
                (@{ permissionType = 'delegated'; clientApplicationIds = @('operator-added-app') } | ConvertTo-Cached)
            ) }
        $Item = [PSCustomObject]@{ Variables = [PSCustomObject]@{} }
        $Prepared = Get-CIPPBaselineOauthConsentState -Item $Item -TenantFilter $script:Tenant
        (Get-Verdict -Expected $Prepared.Expected -Current $Prepared.Current).Count | Should -Be 0
    }

    It 'requires BOTH a delegated and an application include per allowed app' {
        Mock New-CIPPDbRequest { @(@{ permissionGrantPolicyIdsAssignedToDefaultUserRole = @('ManagePermissionGrantsForSelf.cipp-consent-policy') } | ConvertTo-Cached) }
        Mock New-GraphGetRequest { @(
                (@{ permissionType = 'delegated'; clientApplicationIds = @('00b41c95-dab0-4487-9791-b9d2c32c80f2') } | ConvertTo-Cached),
                (@{ permissionType = 'delegated'; clientApplicationIds = @('app-1') } | ConvertTo-Cached)
            ) }
        $Item = [PSCustomObject]@{ Variables = [PSCustomObject]@{ AllowedApps = 'app-1' } }
        $Prepared = Get-CIPPBaselineOauthConsentState -Item $Item -TenantFilter $script:Tenant
        $Prepared.Current.missingIncludes | Should -Be @('application|app-1')
    }
}

Describe 'Get-CIPPBaselineDisableSelfServiceLicensesState' {
    BeforeAll {
        $script:Products = @(
            @{ productId = 'CFQ7TTC0KP0N'; productName = 'Power Automate'; policyValue = 'Enabled' }
            @{ productId = 'CFQ7TTC0KXG7'; productName = 'Power BI Pro'; policyValue = 'Disabled' }
            @{ productId = 'autoclaim'; productName = 'Trial Autoclaim'; policyValue = 'Enabled' }
        )
    }

    It 'excluded product ids are expected Enabled, everything else Disabled' {
        Mock New-CIPPDbRequest {
            if ($Type -eq 'SelfServicePurchaseProducts') { @($script:Products | ConvertTo-Cached) }
            else { @(@{ allowedToSignUpEmailBasedSubscriptions = $false } | ConvertTo-Cached) }
        }
        $Item = [PSCustomObject]@{ Variables = [PSCustomObject]@{ Exclusions = 'CFQ7TTC0KP0N' } }
        $Prepared = Get-CIPPBaselineDisableSelfServiceLicensesState -Item $Item -TenantFilter $script:Tenant
        @($Prepared.Current.productsOutOfPolicy).Count | Should -Be 0
    }

    It 'grades autoclaim only when trials are disabled, and routes each offender to its endpoint' {
        Mock New-CIPPDbRequest {
            if ($Type -eq 'SelfServicePurchaseProducts') { @($script:Products | ConvertTo-Cached) }
            else { @(@{ allowedToSignUpEmailBasedSubscriptions = $true } | ConvertTo-Cached) }
        }
        $Item = [PSCustomObject]@{ Variables = [PSCustomObject]@{ DisableTrials = $true } }
        $Prepared = Get-CIPPBaselineDisableSelfServiceLicensesState -Item $Item -TenantFilter $script:Tenant
        $Prepared.Current.productsOutOfPolicy | Should -Contain 'Trial Autoclaim'
        $Prepared.Current.productsOutOfPolicy | Should -Contain 'Email Based Subscriptions'
        Mock New-GraphPostRequest { }
        Invoke-CIPPBaselineDisableSelfServiceLicenses -Remediate $null -TenantFilter $script:Tenant -Current $Prepared.Current
        Should -Invoke New-GraphPostRequest -ParameterFilter { $uri -match 'autoclaim' }
        Should -Invoke New-GraphPostRequest -ParameterFilter { $uri -match 'authorizationPolicy' -and $type -eq 'PATCH' }
        Should -Invoke New-GraphPostRequest -ParameterFilter { $uri -match 'licensing.m365.microsoft.com' -and $type -eq 'PUT' }
    }
}

Describe 'Get-CIPPBaselineCopilotLimitedModeState' {
    It 'disabled posture grades the flag alone - no group needed' {
        Mock New-CIPPDbRequest { @(@{ isEnabledForGroup = $false; groupId = $null } | ConvertTo-Cached) }
        $Item = [PSCustomObject]@{ Variables = [PSCustomObject]@{ LimitedModeEnabled = $false } }
        $Prepared = Get-CIPPBaselineCopilotLimitedModeState -Item $Item -TenantFilter $script:Tenant
        (Get-Verdict -Expected $Prepared.Expected -Current $Prepared.Current).Count | Should -Be 0
    }

    It 'enabled posture with an unresolvable group reports No Data, never a fake verdict' {
        Mock New-CIPPDbRequest {
            if ($Type -eq 'CopilotAdminSettings') { @(@{ isEnabledForGroup = $false; groupId = $null } | ConvertTo-Cached) } else { @() }
        }
        $Item = [PSCustomObject]@{ Variables = [PSCustomObject]@{ LimitedModeEnabled = $true; GroupName = 'Missing Group' } }
        (Get-CIPPBaselineCopilotLimitedModeState -Item $Item -TenantFilter $script:Tenant).Current | Should -BeNullOrEmpty
    }
}
