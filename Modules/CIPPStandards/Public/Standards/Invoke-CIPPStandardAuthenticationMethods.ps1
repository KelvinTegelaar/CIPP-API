function Invoke-CIPPStandardAuthenticationMethods {
    <#
    .FUNCTIONALITY
        Internal
    .COMPONENT
        (APIName) AuthenticationMethods
    .SYNOPSIS
        (Label) Configure Authentication Methods
    .DESCRIPTION
        (Helptext) Configures all authentication methods for the tenant including Microsoft Authenticator, FIDO2, SMS, Voice, Email OTP, Temporary Access Pass, Software OATH, Hardware OATH, Certificate-based, and QR Code Pin. Enable or disable each method and optionally target specific groups.
        (DocsDescription) Unified standard to configure all authentication method policies in a single place. Each method can be independently enabled or disabled, targeted to all users or specific groups using group name wildcards, and configured with method-specific settings such as TAP lifetime, QR code pin length, Authenticator software OTP, and Email OTP external user access with exclude group targeting.
    .NOTES
        CAT
            Entra (AAD) Standards
        TAG
        EXECUTIVETEXT
            Provides centralized control over all tenant authentication methods from a single standard. Administrators can enable phishing-resistant methods like FIDO2 and Microsoft Authenticator while disabling less secure options like SMS and Voice. Each method supports group-level targeting using wildcard group names, allowing staged rollouts and granular control.
        ADDEDCOMPONENT
            {"type":"switch","name":"standards.AuthenticationMethods.MicrosoftAuthenticatorEnabled","label":"Microsoft Authenticator","defaultValue":false}
            {"type":"textField","name":"standards.AuthenticationMethods.MicrosoftAuthenticatorGroup","label":"Target Group Name (wildcard supported, blank = All Users)","required":false,"condition":{"field":"standards.AuthenticationMethods.MicrosoftAuthenticatorEnabled","compareType":"is","compareValue":true}}
            {"type":"switch","name":"standards.AuthenticationMethods.MicrosoftAuthenticatorSoftwareOath","label":"Enable Software OTP in Authenticator","defaultValue":false,"condition":{"field":"standards.AuthenticationMethods.MicrosoftAuthenticatorEnabled","compareType":"is","compareValue":true}}
            {"type":"autoComplete","multiple":false,"creatable":false,"label":"Show Application Name in Push Notifications","name":"standards.AuthenticationMethods.MicrosoftAuthenticatorDisplayAppInfo","options":[{"label":"Microsoft managed","value":"default"},{"label":"Enabled","value":"enabled"},{"label":"Disabled","value":"disabled"}],"condition":{"field":"standards.AuthenticationMethods.MicrosoftAuthenticatorEnabled","compareType":"is","compareValue":true}}
            {"type":"autoComplete","multiple":false,"creatable":false,"label":"Show Geographic Location in Push Notifications","name":"standards.AuthenticationMethods.MicrosoftAuthenticatorDisplayLocation","options":[{"label":"Microsoft managed","value":"default"},{"label":"Enabled","value":"enabled"},{"label":"Disabled","value":"disabled"}],"condition":{"field":"standards.AuthenticationMethods.MicrosoftAuthenticatorEnabled","compareType":"is","compareValue":true}}
            {"type":"autoComplete","multiple":false,"creatable":false,"label":"Companion App (Authenticator Lite)","name":"standards.AuthenticationMethods.MicrosoftAuthenticatorCompanionApp","options":[{"label":"Microsoft managed","value":"default"},{"label":"Enabled","value":"enabled"},{"label":"Disabled","value":"disabled"}],"condition":{"field":"standards.AuthenticationMethods.MicrosoftAuthenticatorEnabled","compareType":"is","compareValue":true}}
            {"type":"switch","name":"standards.AuthenticationMethods.FIDO2Enabled","label":"FIDO2 Security Keys","defaultValue":false}
            {"type":"textField","name":"standards.AuthenticationMethods.FIDO2Group","label":"Target Group Name (wildcard supported, blank = All Users)","required":false,"condition":{"field":"standards.AuthenticationMethods.FIDO2Enabled","compareType":"is","compareValue":true}}
            {"type":"switch","name":"standards.AuthenticationMethods.TAPEnabled","label":"Temporary Access Pass","defaultValue":false}
            {"type":"textField","name":"standards.AuthenticationMethods.TAPGroup","label":"Target Group Name (wildcard supported, blank = All Users)","required":false,"condition":{"field":"standards.AuthenticationMethods.TAPEnabled","compareType":"is","compareValue":true}}
            {"type":"autoComplete","multiple":false,"creatable":false,"label":"TAP Usage Mode","name":"standards.AuthenticationMethods.TAPUsableOnce","options":[{"label":"Only Once","value":"true"},{"label":"Multiple Logons","value":"false"}],"condition":{"field":"standards.AuthenticationMethods.TAPEnabled","compareType":"is","compareValue":true}}
            {"type":"number","name":"standards.AuthenticationMethods.TAPDefaultLifetime","label":"TAP Default Lifetime (minutes)","defaultValue":60,"condition":{"field":"standards.AuthenticationMethods.TAPEnabled","compareType":"is","compareValue":true}}
            {"type":"number","name":"standards.AuthenticationMethods.TAPMinLifetime","label":"TAP Minimum Lifetime (minutes)","defaultValue":60,"condition":{"field":"standards.AuthenticationMethods.TAPEnabled","compareType":"is","compareValue":true}}
            {"type":"number","name":"standards.AuthenticationMethods.TAPMaxLifetime","label":"TAP Maximum Lifetime (minutes)","defaultValue":480,"condition":{"field":"standards.AuthenticationMethods.TAPEnabled","compareType":"is","compareValue":true}}
            {"type":"number","name":"standards.AuthenticationMethods.TAPDefaultLength","label":"TAP Length (characters)","defaultValue":8,"condition":{"field":"standards.AuthenticationMethods.TAPEnabled","compareType":"is","compareValue":true}}
            {"type":"switch","name":"standards.AuthenticationMethods.SoftwareOathEnabled","label":"Third-Party Software OATH Tokens","defaultValue":false}
            {"type":"textField","name":"standards.AuthenticationMethods.SoftwareOathGroup","label":"Target Group Name (wildcard supported, blank = All Users)","required":false,"condition":{"field":"standards.AuthenticationMethods.SoftwareOathEnabled","compareType":"is","compareValue":true}}
            {"type":"switch","name":"standards.AuthenticationMethods.HardwareOathEnabled","label":"Hardware OATH Tokens","defaultValue":false}
            {"type":"textField","name":"standards.AuthenticationMethods.HardwareOathGroup","label":"Target Group Name (wildcard supported, blank = All Users)","required":false,"condition":{"field":"standards.AuthenticationMethods.HardwareOathEnabled","compareType":"is","compareValue":true}}
            {"type":"switch","name":"standards.AuthenticationMethods.SMSEnabled","label":"SMS","defaultValue":false}
            {"type":"textField","name":"standards.AuthenticationMethods.SMSGroup","label":"Target Group Name (wildcard supported, blank = All Users)","required":false,"condition":{"field":"standards.AuthenticationMethods.SMSEnabled","compareType":"is","compareValue":true}}
            {"type":"switch","name":"standards.AuthenticationMethods.VoiceEnabled","label":"Voice Call","defaultValue":false}
            {"type":"textField","name":"standards.AuthenticationMethods.VoiceGroup","label":"Target Group Name (wildcard supported, blank = All Users)","required":false,"condition":{"field":"standards.AuthenticationMethods.VoiceEnabled","compareType":"is","compareValue":true}}
            {"type":"switch","name":"standards.AuthenticationMethods.EmailEnabled","label":"Email OTP","defaultValue":false}
            {"type":"textField","name":"standards.AuthenticationMethods.EmailGroup","label":"Target Group Name (wildcard supported, blank = All Users)","required":false,"condition":{"field":"standards.AuthenticationMethods.EmailEnabled","compareType":"is","compareValue":true}}
            {"type":"autoComplete","multiple":false,"creatable":false,"label":"Allow external users to use Email OTP","name":"standards.AuthenticationMethods.EmailAllowExternalIdToUseEmailOtp","options":[{"label":"Microsoft managed (default)","value":"default"},{"label":"Enabled","value":"enabled"},{"label":"Disabled","value":"disabled"}],"condition":{"field":"standards.AuthenticationMethods.EmailEnabled","compareType":"is","compareValue":true}}
            {"type":"textField","name":"standards.AuthenticationMethods.EmailExcludeGroup","label":"Exclude Group Name (wildcard supported, blank = no exclusions)","required":false,"condition":{"field":"standards.AuthenticationMethods.EmailEnabled","compareType":"is","compareValue":true}}
            {"type":"switch","name":"standards.AuthenticationMethods.x509CertificateEnabled","label":"Certificate-Based Authentication","defaultValue":false}
            {"type":"textField","name":"standards.AuthenticationMethods.x509CertificateGroup","label":"Target Group Name (wildcard supported, blank = All Users)","required":false,"condition":{"field":"standards.AuthenticationMethods.x509CertificateEnabled","compareType":"is","compareValue":true}}
            {"type":"switch","name":"standards.AuthenticationMethods.QRCodePinEnabled","label":"QR Code Pin","defaultValue":false}
            {"type":"textField","name":"standards.AuthenticationMethods.QRCodePinGroup","label":"Target Group Name (wildcard supported, blank = All Users)","required":false,"condition":{"field":"standards.AuthenticationMethods.QRCodePinEnabled","compareType":"is","compareValue":true}}
            {"type":"number","name":"standards.AuthenticationMethods.QRCodeLifetimeInDays","label":"QR Code Lifetime (days, 1-395)","defaultValue":365,"condition":{"field":"standards.AuthenticationMethods.QRCodePinEnabled","compareType":"is","compareValue":true}}
            {"type":"number","name":"standards.AuthenticationMethods.QRCodePinLength","label":"QR Code PIN Length (8-20)","defaultValue":8,"condition":{"field":"standards.AuthenticationMethods.QRCodePinEnabled","compareType":"is","compareValue":true}}
        IMPACT
            High Impact
        ADDEDDATE
            2026-05-28
        POWERSHELLEQUIVALENT
            Update-MgBetaPolicyAuthenticationMethodPolicyAuthenticationMethodConfiguration
        RECOMMENDEDBY
            "CIPP"
        DISABLEDFEATURES
            {"report":false,"warn":false,"remediate":false}
        UPDATECOMMENTBLOCK
            Run the Tools\Update-StandardsComments.ps1 script to update this comment block
    .LINK
        https://docs.cipp.app/user-documentation/tenant/standards/alignment/templates/available-standards
    #>

    param($Tenant, $Settings)

    # Map of method IDs used in the Graph API to our setting key names
    # 'Id' matches the Graph API response id for lookups from the full policy
    # 'RemediationId' matches the Set-CIPPAuthenticationPolicy ValidateSet for PATCH calls
    $AuthMethods = @(
        @{ Id = 'MicrosoftAuthenticator'; RemediationId = 'MicrosoftAuthenticator'; SettingKey = 'MicrosoftAuthenticator'; Label = 'Microsoft Authenticator' }
        @{ Id = 'Fido2'; RemediationId = 'FIDO2'; SettingKey = 'FIDO2'; Label = 'FIDO2 Security Keys' }
        @{ Id = 'TemporaryAccessPass'; RemediationId = 'TemporaryAccessPass'; SettingKey = 'TAP'; Label = 'Temporary Access Pass' }
        @{ Id = 'softwareOath'; RemediationId = 'softwareOath'; SettingKey = 'SoftwareOath'; Label = 'Software OATH Tokens' }
        @{ Id = 'HardwareOath'; RemediationId = 'HardwareOATH'; SettingKey = 'HardwareOath'; Label = 'Hardware OATH Tokens' }
        @{ Id = 'Sms'; RemediationId = 'SMS'; SettingKey = 'SMS'; Label = 'SMS' }
        @{ Id = 'Voice'; RemediationId = 'Voice'; SettingKey = 'Voice'; Label = 'Voice Call' }
        @{ Id = 'Email'; RemediationId = 'Email'; SettingKey = 'Email'; Label = 'Email OTP' }
        @{ Id = 'x509Certificate'; RemediationId = 'x509Certificate'; SettingKey = 'x509Certificate'; Label = 'Certificate-Based Authentication' }
        @{ Id = 'QRCodePin'; RemediationId = 'QRCodePin'; SettingKey = 'QRCodePin'; Label = 'QR Code Pin' }
    )

    # Determine which methods the user has explicitly configured
    $ConfiguredMethods = foreach ($Method in $AuthMethods) {
        $EnabledKey = "$($Method.SettingKey)Enabled"
        $EnabledValue = $Settings.$EnabledKey
        if ($null -eq $EnabledValue) { continue }
        $GroupName = $Settings."$($Method.SettingKey)Group"
        $ExcludeGroupName = $Settings."$($Method.SettingKey)ExcludeGroup"
        [PSCustomObject]@{
            Id               = $Method.Id
            RemediationId    = $Method.RemediationId
            Key              = $Method.SettingKey
            Label            = $Method.Label
            Enabled          = [bool]$EnabledValue
            GroupName        = if ([string]::IsNullOrWhiteSpace($GroupName)) { $null } else { $GroupName }
            ExcludeGroupName = if ([string]::IsNullOrWhiteSpace($ExcludeGroupName)) { $null } else { $ExcludeGroupName }
        }
    }

    if (-not $ConfiguredMethods -or $ConfiguredMethods.Count -eq 0) {
        Write-LogMessage -API 'Standards' -tenant $Tenant -message 'AuthenticationMethods: No authentication methods configured, skipping.' -sev Info
        return
    }

    try {
        $FullPolicy = New-GraphGetRequest -Uri 'https://graph.microsoft.com/beta/policies/authenticationMethodsPolicy' -tenantid $Tenant -AsApp $true
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Write-LogMessage -API 'Standards' -tenant $Tenant -message "AuthenticationMethods: Could not retrieve authentication methods policy. Error: $($ErrorMessage.NormalizedError)" -sev Error -LogData $ErrorMessage
        return
    }

    # Index the method configurations by ID for fast lookup
    $CurrentConfigs = @{}
    foreach ($Config in $FullPolicy.authenticationMethodConfigurations) {
        $CurrentConfigs[$Config.id] = $Config
    }

    # Resolve group names to IDs (cached to avoid duplicate lookups)
    $GroupIdCache = @{}
    foreach ($Method in $ConfiguredMethods) {
        if ($Method.Enabled -and $Method.GroupName -and -not $GroupIdCache.ContainsKey($Method.GroupName)) {
            try {
                $EscapedName = $Method.GroupName -replace "'", "''"
                $GroupFilter = [System.Uri]::EscapeDataString("startsWith(displayName,'$EscapedName')")
                $MatchedGroups = @(New-GraphGetRequest -uri "https://graph.microsoft.com/beta/groups?`$select=id,displayName&`$filter=$GroupFilter" -tenantid $Tenant)
                if ($MatchedGroups.Count -gt 0) {
                    $GroupIdCache[$Method.GroupName] = @($MatchedGroups | ForEach-Object { $_.id })
                    if ($MatchedGroups.Count -gt 1) {
                        Write-LogMessage -API 'Standards' -tenant $Tenant -message "AuthenticationMethods: Multiple groups matched '$($Method.GroupName)': $($MatchedGroups.displayName -join ', ')" -sev Info
                    }
                } else {
                    Write-LogMessage -API 'Standards' -tenant $Tenant -message "AuthenticationMethods: No group found matching '$($Method.GroupName)'" -sev Warning
                    $GroupIdCache[$Method.GroupName] = $null
                }
            } catch {
                $ErrorMessage = Get-CippException -Exception $_
                Write-LogMessage -API 'Standards' -tenant $Tenant -message "AuthenticationMethods: Failed to resolve group '$($Method.GroupName)'. Error: $($ErrorMessage.NormalizedError)" -sev Error -LogData $ErrorMessage
                $GroupIdCache[$Method.GroupName] = $null
            }
        }
        if ($Method.Enabled -and $Method.ExcludeGroupName -and -not $GroupIdCache.ContainsKey($Method.ExcludeGroupName)) {
            try {
                $EscapedName = $Method.ExcludeGroupName -replace "'", "''"
                $GroupFilter = [System.Uri]::EscapeDataString("startsWith(displayName,'$EscapedName')")
                $MatchedGroups = @(New-GraphGetRequest -uri "https://graph.microsoft.com/beta/groups?`$select=id,displayName&`$filter=$GroupFilter" -tenantid $Tenant)
                if ($MatchedGroups.Count -gt 0) {
                    $GroupIdCache[$Method.ExcludeGroupName] = @($MatchedGroups | ForEach-Object { $_.id })
                    if ($MatchedGroups.Count -gt 1) {
                        Write-LogMessage -API 'Standards' -tenant $Tenant -message "AuthenticationMethods: Multiple exclude groups matched '$($Method.ExcludeGroupName)': $($MatchedGroups.displayName -join ', ')" -sev Info
                    }
                } else {
                    Write-LogMessage -API 'Standards' -tenant $Tenant -message "AuthenticationMethods: No exclude group found matching '$($Method.ExcludeGroupName)'" -sev Warning
                    $GroupIdCache[$Method.ExcludeGroupName] = $null
                }
            } catch {
                $ErrorMessage = Get-CippException -Exception $_
                Write-LogMessage -API 'Standards' -tenant $Tenant -message "AuthenticationMethods: Failed to resolve exclude group '$($Method.ExcludeGroupName)'. Error: $($ErrorMessage.NormalizedError)" -sev Error -LogData $ErrorMessage
                $GroupIdCache[$Method.ExcludeGroupName] = $null
            }
        }
    }

    # --- Build expected vs current state and check compliance per method ---
    $ComplianceResults = foreach ($Method in $ConfiguredMethods) {
        $CurrentConfig = $CurrentConfigs[$Method.Id]
        if (-not $CurrentConfig) {
            Write-LogMessage -API 'Standards' -tenant $Tenant -message "AuthenticationMethods: Method '$($Method.Label)' not found in policy response." -sev Warning
            continue
        }

        $DesiredState = if ($Method.Enabled) { 'enabled' } else { 'disabled' }
        $Drifts = [System.Collections.Generic.List[string]]::new()

        # -- State check --
        if ($CurrentConfig.state -ne $DesiredState) {
            $Drifts.Add("state: '$($CurrentConfig.state)' -> '$DesiredState'")
        }

        # -- Group targeting check (compare only targetType + id, ignore API-added properties) --
        $CurrentTargetIds = @($CurrentConfig.includeTargets | ForEach-Object { $_.id })
        if ($Method.Enabled -and $Method.GroupName) {
            $ResolvedGroupIds = $GroupIdCache[$Method.GroupName]
            if ($ResolvedGroupIds) {
                $Diff = Compare-Object -ReferenceObject @($ResolvedGroupIds | Sort-Object) -DifferenceObject @($CurrentTargetIds | Sort-Object) -ErrorAction SilentlyContinue
                if ($Diff) {
                    $Drifts.Add("includeTargets: current [$($CurrentTargetIds -join ', ')] -> expected [$($ResolvedGroupIds -join ', ')]")
                }
            }
        } elseif ($Method.Enabled) {
            if ('all_users' -notin $CurrentTargetIds) {
                $Drifts.Add("includeTargets: current [$($CurrentTargetIds -join ', ')] -> expected [all_users]")
            }
        }

        # Build normalized includeTargets for expected config (only the properties we manage)
        if ($Method.Enabled -and $Method.GroupName) {
            $ResolvedGroupIds = $GroupIdCache[$Method.GroupName]
            if ($ResolvedGroupIds) {
                $NormalizedTargets = @($ResolvedGroupIds | ForEach-Object { @{ targetType = 'group'; id = $_ } })
            } else {
                $NormalizedTargets = @($CurrentConfig.includeTargets | ForEach-Object { @{ targetType = $_.targetType; id = $_.id } })
            }
        } elseif ($Method.Enabled) {
            $NormalizedTargets = @(@{ targetType = 'group'; id = 'all_users' })
        } else {
            # Disabled: mirror current targets (we don't manage them)
            $NormalizedTargets = @($CurrentConfig.includeTargets | ForEach-Object { @{ targetType = $_.targetType; id = $_.id } })
        }

        # -- Build expected config with all comparable properties --
        $ExpectedConfig = @{
            state          = $DesiredState
            includeTargets = $NormalizedTargets
        }

        switch ($Method.Id) {
            'MicrosoftAuthenticator' {
                if ($Method.Enabled) {
                    $DesiredSoftwareOath = [bool]$Settings.MicrosoftAuthenticatorSoftwareOath
                    $ExpectedConfig['isSoftwareOathEnabled'] = $DesiredSoftwareOath
                    if ($CurrentConfig.isSoftwareOathEnabled -ne $DesiredSoftwareOath) {
                        $Drifts.Add("isSoftwareOathEnabled: '$($CurrentConfig.isSoftwareOathEnabled)' -> '$DesiredSoftwareOath'")
                    }

                    # Feature settings: each has a .state property
                    $FeatureMap = @(
                        @{ Setting = 'MicrosoftAuthenticatorDisplayAppInfo'; Property = 'displayAppInformationRequiredState'; Label = 'Display App Info' }
                        @{ Setting = 'MicrosoftAuthenticatorDisplayLocation'; Property = 'displayLocationInformationRequiredState'; Label = 'Display Location' }
                        @{ Setting = 'MicrosoftAuthenticatorCompanionApp'; Property = 'companionAppAllowedState'; Label = 'Companion App' }
                    )
                    foreach ($Feature in $FeatureMap) {
                        $DesiredFeatureState = $Settings."$($Feature.Setting)".value ?? $Settings."$($Feature.Setting)"
                        if ($DesiredFeatureState) {
                            $CurrentFeatureState = $CurrentConfig.featureSettings."$($Feature.Property)".state
                            $ExpectedConfig["featureSettings.$($Feature.Property)"] = $DesiredFeatureState
                            if ($CurrentFeatureState -ne $DesiredFeatureState) {
                                $Drifts.Add("$($Feature.Label): '$CurrentFeatureState' -> '$DesiredFeatureState'")
                            }
                        }
                    }
                }
            }
            'TemporaryAccessPass' {
                if ($Method.Enabled) {
                    $TAPUsableOnce = $Settings.TAPUsableOnce.value ?? $Settings.TAPUsableOnce ?? 'true'
                    $TAPUsableOnceBool = [System.Convert]::ToBoolean($TAPUsableOnce)
                    $TAPDefaultLifetime = [int]($Settings.TAPDefaultLifetime ?? 60)
                    $TAPMinLifetime = [int]($Settings.TAPMinLifetime ?? 60)
                    $TAPMaxLifetime = [int]($Settings.TAPMaxLifetime ?? 480)
                    $TAPDefaultLength = [int]($Settings.TAPDefaultLength ?? 8)

                    $ExpectedConfig['isUsableOnce'] = $TAPUsableOnceBool
                    $ExpectedConfig['defaultLifetimeInMinutes'] = $TAPDefaultLifetime
                    $ExpectedConfig['minimumLifetimeInMinutes'] = $TAPMinLifetime
                    $ExpectedConfig['maximumLifetimeInMinutes'] = $TAPMaxLifetime
                    $ExpectedConfig['defaultLength'] = $TAPDefaultLength

                    if ([System.Convert]::ToBoolean($CurrentConfig.isUsableOnce) -ne $TAPUsableOnceBool) {
                        $Drifts.Add("isUsableOnce: '$($CurrentConfig.isUsableOnce)' -> '$TAPUsableOnceBool'")
                    }
                    if ([int]$CurrentConfig.defaultLifetimeInMinutes -ne $TAPDefaultLifetime) {
                        $Drifts.Add("defaultLifetimeInMinutes: '$($CurrentConfig.defaultLifetimeInMinutes)' -> '$TAPDefaultLifetime'")
                    }
                    if ([int]$CurrentConfig.minimumLifetimeInMinutes -ne $TAPMinLifetime) {
                        $Drifts.Add("minimumLifetimeInMinutes: '$($CurrentConfig.minimumLifetimeInMinutes)' -> '$TAPMinLifetime'")
                    }
                    if ([int]$CurrentConfig.maximumLifetimeInMinutes -ne $TAPMaxLifetime) {
                        $Drifts.Add("maximumLifetimeInMinutes: '$($CurrentConfig.maximumLifetimeInMinutes)' -> '$TAPMaxLifetime'")
                    }
                    if ([int]$CurrentConfig.defaultLength -ne $TAPDefaultLength) {
                        $Drifts.Add("defaultLength: '$($CurrentConfig.defaultLength)' -> '$TAPDefaultLength'")
                    }
                }
            }
            'QRCodePin' {
                if ($Method.Enabled) {
                    $DesiredLifetime = [int]($Settings.QRCodeLifetimeInDays ?? 365)
                    $DesiredPinLength = [int]($Settings.QRCodePinLength ?? 8)

                    $ExpectedConfig['standardQRCodeLifetimeInDays'] = $DesiredLifetime
                    $ExpectedConfig['pinLength'] = $DesiredPinLength

                    if ([int]$CurrentConfig.standardQRCodeLifetimeInDays -ne $DesiredLifetime) {
                        $Drifts.Add("standardQRCodeLifetimeInDays: '$($CurrentConfig.standardQRCodeLifetimeInDays)' -> '$DesiredLifetime'")
                    }
                    if ([int]$CurrentConfig.pinLength -ne $DesiredPinLength) {
                        $Drifts.Add("pinLength: '$($CurrentConfig.pinLength)' -> '$DesiredPinLength'")
                    }
                }
            }
            'Email' {
                if ($Method.Enabled) {
                    $DesiredExternalOtp = $Settings.EmailAllowExternalIdToUseEmailOtp.value ?? $Settings.EmailAllowExternalIdToUseEmailOtp
                    if ($DesiredExternalOtp) {
                        $ExpectedConfig['allowExternalIdToUseEmailOtp'] = $DesiredExternalOtp
                        if ($CurrentConfig.allowExternalIdToUseEmailOtp -ne $DesiredExternalOtp) {
                            $Drifts.Add("allowExternalIdToUseEmailOtp: '$($CurrentConfig.allowExternalIdToUseEmailOtp)' -> '$DesiredExternalOtp'")
                        }
                    }

                    # Exclude targets check
                    if ($Method.ExcludeGroupName) {
                        $ResolvedExcludeIds = $GroupIdCache[$Method.ExcludeGroupName]
                        if ($ResolvedExcludeIds) {
                            $NormalizedExcludeTargets = @($ResolvedExcludeIds | ForEach-Object { @{ targetType = 'group'; id = $_ } })
                            $ExpectedConfig['excludeTargets'] = $NormalizedExcludeTargets
                            $CurrentExcludeIds = @($CurrentConfig.excludeTargets | ForEach-Object { $_.id })
                            $ExcludeDiff = Compare-Object -ReferenceObject @($ResolvedExcludeIds | Sort-Object) -DifferenceObject @($CurrentExcludeIds | Sort-Object) -ErrorAction SilentlyContinue
                            if ($ExcludeDiff) {
                                $Drifts.Add("excludeTargets: current [$($CurrentExcludeIds -join ', ')] -> expected [$($ResolvedExcludeIds -join ', ')]")
                            }
                        }
                    }
                }
            }
        }

        [PSCustomObject]@{
            Method         = $Method
            CurrentConfig  = $CurrentConfig
            ExpectedConfig = [PSCustomObject]$ExpectedConfig
            DesiredState   = $DesiredState
            Drifts         = $Drifts
            IsCompliant    = $Drifts.Count -eq 0
        }
    }

    if ($Settings.remediate -eq $true) {
        foreach ($Result in $ComplianceResults) {
            if ($Result.IsCompliant) {
                Write-LogMessage -API 'Standards' -tenant $Tenant -message "AuthenticationMethods: $($Result.Method.Label) is already configured correctly." -sev Info
                continue
            }

            try {
                $Params = @{
                    Tenant                 = $Tenant
                    APIName                = 'Standards'
                    AuthenticationMethodId = $Result.Method.RemediationId
                    Enabled                = $Result.Method.Enabled
                }

                # Add group targeting
                if ($Result.Method.Enabled -and $Result.Method.GroupName) {
                    $ResolvedGroupIds = $GroupIdCache[$Result.Method.GroupName]
                    if ($ResolvedGroupIds) {
                        $Params['GroupIds'] = $ResolvedGroupIds
                    }
                }

                # Add method-specific parameters
                switch ($Result.Method.Id) {
                    'MicrosoftAuthenticator' {
                        if ($Result.Method.Enabled) {
                            $Params['MicrosoftAuthenticatorSoftwareOathEnabled'] = [bool]$Settings.MicrosoftAuthenticatorSoftwareOath
                            $DisplayAppInfo = $Settings.MicrosoftAuthenticatorDisplayAppInfo.value ?? $Settings.MicrosoftAuthenticatorDisplayAppInfo
                            $DisplayLocation = $Settings.MicrosoftAuthenticatorDisplayLocation.value ?? $Settings.MicrosoftAuthenticatorDisplayLocation
                            $CompanionApp = $Settings.MicrosoftAuthenticatorCompanionApp.value ?? $Settings.MicrosoftAuthenticatorCompanionApp
                            if ($DisplayAppInfo) { $Params['MicrosoftAuthenticatorDisplayAppInfo'] = $DisplayAppInfo }
                            if ($DisplayLocation) { $Params['MicrosoftAuthenticatorDisplayLocation'] = $DisplayLocation }
                            if ($CompanionApp) { $Params['MicrosoftAuthenticatorCompanionApp'] = $CompanionApp }
                        }
                    }
                    'TemporaryAccessPass' {
                        if ($Result.Method.Enabled) {
                            $TAPUsableOnce = $Settings.TAPUsableOnce.value ?? $Settings.TAPUsableOnce ?? 'true'
                            $Params['TAPisUsableOnce'] = $TAPUsableOnce
                            $Params['TAPDefaultLifeTime'] = [int]($Settings.TAPDefaultLifetime ?? 60)
                            $Params['TAPMinimumLifetime'] = [int]($Settings.TAPMinLifetime ?? 60)
                            $Params['TAPMaximumLifetime'] = [int]($Settings.TAPMaxLifetime ?? 480)
                            $Params['TAPDefaultLength'] = [int]($Settings.TAPDefaultLength ?? 8)
                        }
                    }
                    'QRCodePin' {
                        if ($Result.Method.Enabled) {
                            $Params['QRCodeLifetimeInDays'] = [int]($Settings.QRCodeLifetimeInDays ?? 365)
                            $Params['QRCodePinLength'] = [int]($Settings.QRCodePinLength ?? 8)
                        }
                    }
                    'Email' {
                        if ($Result.Method.Enabled) {
                            $DesiredExternalOtp = $Settings.EmailAllowExternalIdToUseEmailOtp.value ?? $Settings.EmailAllowExternalIdToUseEmailOtp
                            if ($DesiredExternalOtp) {
                                $Params['EmailAllowExternalIdToUseEmailOtp'] = $DesiredExternalOtp
                            }
                            if ($Result.Method.ExcludeGroupName) {
                                $ResolvedExcludeIds = $GroupIdCache[$Result.Method.ExcludeGroupName]
                                if ($ResolvedExcludeIds) {
                                    $Params['EmailExcludeGroupIds'] = $ResolvedExcludeIds
                                }
                            }
                        }
                    }
                }

                Set-CIPPAuthenticationPolicy @Params
                Write-LogMessage -API 'Standards' -tenant $Tenant -message "AuthenticationMethods: Remediated $($Result.Method.Label). Changes: $($Result.Drifts -join '; ')" -sev Info
            } catch {
                $ErrorMessage = Get-CippException -Exception $_
                Write-LogMessage -API 'Standards' -tenant $Tenant -message "AuthenticationMethods: Failed to configure $($Result.Method.Label). Error: $($ErrorMessage.NormalizedError)" -sev Error -LogData $ErrorMessage
            }
        }
    }

    if ($Settings.alert -eq $true) {
        $NonCompliant = @($ComplianceResults | Where-Object { -not $_.IsCompliant })
        if ($NonCompliant.Count -eq 0) {
            Write-LogMessage -API 'Standards' -tenant $Tenant -message 'AuthenticationMethods: All configured authentication methods are compliant.' -sev Info
        } else {
            $AlertDetails = foreach ($Result in $NonCompliant) {
                [PSCustomObject]@{
                    Method = $Result.Method.Label
                    Drifts = $Result.Drifts -join '; '
                }
            }
            Write-StandardsAlert -message "AuthenticationMethods: $($NonCompliant.Count) method(s) not compliant: $(($NonCompliant.Method.Label) -join ', ')" -object $AlertDetails -tenant $Tenant -standardName 'AuthenticationMethods' -standardId $Settings.standardId
            Write-LogMessage -API 'Standards' -tenant $Tenant -message "AuthenticationMethods: $($NonCompliant.Count) method(s) not compliant." -sev Info
        }
    }

    if ($Settings.report -eq $true) {
        $CurrentValue = @{}
        $ExpectedValue = @{}
        foreach ($Result in $ComplianceResults) {
            $CompareProperties = @($Result.ExpectedConfig.PSObject.Properties.Name)
            $CurrentSnapshot = @{}
            foreach ($Prop in $CompareProperties) {
                if ($Prop -like 'featureSettings.*') {
                    $SubProp = $Prop -replace '^featureSettings\.', ''
                    $CurrentSnapshot[$Prop] = $Result.CurrentConfig.featureSettings.$SubProp.state
                } elseif ($Prop -eq 'includeTargets') {
                    # Normalize current targets to only targetType + id for comparison
                    $CurrentSnapshot[$Prop] = @($Result.CurrentConfig.includeTargets | ForEach-Object {
                            @{ targetType = $_.targetType; id = $_.id }
                        })
                } elseif ($Prop -eq 'excludeTargets') {
                    $CurrentSnapshot[$Prop] = @($Result.CurrentConfig.excludeTargets | ForEach-Object {
                            @{ targetType = $_.targetType; id = $_.id }
                        })
                } else {
                    $CurrentSnapshot[$Prop] = $Result.CurrentConfig.$Prop
                }
            }
            $CurrentValue[$Result.Method.Key] = [PSCustomObject]$CurrentSnapshot
            $ExpectedValue[$Result.Method.Key] = $Result.ExpectedConfig
        }
        Set-CIPPStandardsCompareField -FieldName 'standards.AuthenticationMethods' -CurrentValue ([PSCustomObject]$CurrentValue) -ExpectedValue ([PSCustomObject]$ExpectedValue) -TenantFilter $Tenant
        $AllCompliant = -not ($ComplianceResults | Where-Object { -not $_.IsCompliant })
        Add-CIPPBPAField -FieldName 'AuthenticationMethods' -FieldValue ([bool]$AllCompliant) -StoreAs bool -Tenant $Tenant
    }
}
