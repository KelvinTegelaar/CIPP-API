function Get-CIPPBaselineAuthenticationMethodsState {
    <#
    .SYNOPSIS
        Prepare hook for AuthenticationMethods: per-method state, targeting and settings
        across the authentication methods policy.
    .DESCRIPTION
        The classic's ten-method matrix, ported whole. Only methods the operator configured
        grade at all; each graded method contributes its drifts - state, include-target
        set (a named group resolved from the Groups cache, or all_users), and the
        method-specific extras: Microsoft Authenticator's software OATH flag and three
        feature states, Temporary Access Pass's five numbers, QR code's two, and Email
        OTP's external-id flag and exclude targets.

        The graded shape is one list naming every drift, so the row reads as findings
        rather than a wall of per-method columns. Everything the executor needs - one
        Set-CIPPAuthenticationPolicy parameter set per drifted method - is carried, built
        here because it depends on the same group resolution the grade used.

        A configured group name that resolves to nothing skips that method's targeting
        grade exactly as the classic skipped it - half-resolved targeting must not drive
        a write.
    .FUNCTIONALITY
        Internal
    #>
    [CmdletBinding()]
    param(
        $Item,
        $TenantFilter
    )

    $Policy = @(Get-CIPPBaselineCacheRows -TenantFilter $TenantFilter -Type 'AuthenticationMethodsPolicy') | Select-Object -First 1
    if (-not $Policy) { return @{ Current = $null } }

    $V = $Item.Variables
    $AuthMethods = @(
        @{ Id = 'MicrosoftAuthenticator'; RemediationId = 'MicrosoftAuthenticator'; Key = 'MicrosoftAuthenticator'; Label = 'Microsoft Authenticator' }
        @{ Id = 'Fido2'; RemediationId = 'FIDO2'; Key = 'FIDO2'; Label = 'FIDO2 Security Keys' }
        @{ Id = 'TemporaryAccessPass'; RemediationId = 'TemporaryAccessPass'; Key = 'TAP'; Label = 'Temporary Access Pass' }
        @{ Id = 'softwareOath'; RemediationId = 'softwareOath'; Key = 'SoftwareOath'; Label = 'Software OATH Tokens' }
        @{ Id = 'HardwareOath'; RemediationId = 'HardwareOATH'; Key = 'HardwareOath'; Label = 'Hardware OATH Tokens' }
        @{ Id = 'Sms'; RemediationId = 'SMS'; Key = 'SMS'; Label = 'SMS' }
        @{ Id = 'Voice'; RemediationId = 'Voice'; Key = 'Voice'; Label = 'Voice Call' }
        @{ Id = 'Email'; RemediationId = 'Email'; Key = 'Email'; Label = 'Email OTP' }
        @{ Id = 'x509Certificate'; RemediationId = 'x509Certificate'; Key = 'x509Certificate'; Label = 'Certificate-Based Authentication' }
        @{ Id = 'QRCodePin'; RemediationId = 'QRCodePin'; Key = 'QRCodePin'; Label = 'QR Code Pin' }
    )

    $Configured = @(foreach ($Method in $AuthMethods) {
            # Formerly a switch (raw boolean), now a three-state autoComplete whose option
            # wrapper the pipeline already unwrapped to $true/$false/'notConfigured'. Legacy
            # booleans and the new values both land here; 'notConfigured' skips the method
            # exactly like an absent variable - the tenant's current setting is never graded.
            $Enabled = $V."$($Method.Key)Enabled"
            $Enabled = $Enabled.value ?? $Enabled
            if ($null -eq $Enabled -or "$Enabled" -eq '' -or "$Enabled" -eq 'notConfigured') { continue }
            [PSCustomObject]@{
                Id = $Method.Id; RemediationId = $Method.RemediationId; Key = $Method.Key; Label = $Method.Label
                Enabled = [bool]($Enabled -eq $true -or "$Enabled" -eq 'True' -or "$Enabled" -eq 'enabled')
                GroupName = "$($V."$($Method.Key)Group")"
                ExcludeGroupName = "$($V."$($Method.Key)ExcludeGroup")"
            }
        })
    if ($Configured.Count -eq 0) { return @{ Current = $null } }

    $Configs = @{}
    foreach ($Config in @($Policy.authenticationMethodConfigurations)) { $Configs["$($Config.id)"] = $Config }

    $Groups = $null
    $NeedsGroups = @($Configured | Where-Object { $_.Enabled -and (-not [string]::IsNullOrWhiteSpace($_.GroupName) -or -not [string]::IsNullOrWhiteSpace($_.ExcludeGroupName)) }).Count -gt 0
    if ($NeedsGroups) { $Groups = @(Get-CIPPBaselineCacheRows -TenantFilter $TenantFilter -Type 'Groups') }
    $GroupIdCache = @{}
    $ResolveGroup = {
        param($Name)
        if ($GroupIdCache.ContainsKey($Name)) { return $GroupIdCache[$Name] }
        $Ids = @($Groups | Where-Object { "$($_.displayName)".StartsWith($Name) } | ForEach-Object { "$($_.id)" })
        $GroupIdCache[$Name] = $(if ($Ids.Count -gt 0) { $Ids } else { $null })
        $GroupIdCache[$Name]
    }

    $AllDrifts = [System.Collections.Generic.List[string]]::new()
    $RemediationSets = [System.Collections.Generic.List[object]]::new()
    foreach ($Method in $Configured) {
        $Config = $Configs[$Method.Id]
        if (-not $Config) { continue }
        $DesiredState = if ($Method.Enabled) { 'enabled' } else { 'disabled' }
        $Drifts = [System.Collections.Generic.List[string]]::new()
        if ("$($Config.state)" -ne $DesiredState) { $Drifts.Add("$($Method.Label): state '$($Config.state)' should be '$DesiredState'") }

        $CurrentTargetIds = @($Config.includeTargets | ForEach-Object { "$($_.id)" })
        $ResolvedGroupIds = $null
        if ($Method.Enabled -and -not [string]::IsNullOrWhiteSpace($Method.GroupName)) {
            $ResolvedGroupIds = & $ResolveGroup $Method.GroupName
            if ($ResolvedGroupIds) {
                $Diff = Compare-Object -ReferenceObject @($ResolvedGroupIds | Sort-Object) -DifferenceObject @($CurrentTargetIds | Sort-Object) -ErrorAction SilentlyContinue
                if ($Diff) { $Drifts.Add("$($Method.Label): targeting [$($CurrentTargetIds -join ', ')] should be [$($ResolvedGroupIds -join ', ')]") }
            }
        } elseif ($Method.Enabled) {
            if ('all_users' -notin $CurrentTargetIds) { $Drifts.Add("$($Method.Label): targeting [$($CurrentTargetIds -join ', ')] should be [all_users]") }
        }

        $Params = @{ AuthenticationMethodId = $Method.RemediationId; Enabled = $Method.Enabled }
        if ($Method.Enabled) {
            $Params['GroupIds'] = $(if ($ResolvedGroupIds) { @($ResolvedGroupIds) } else { @('all_users') })
        }
        switch ($Method.Id) {
            'MicrosoftAuthenticator' {
                if ($Method.Enabled) {
                    $SoftwareOath = [bool]($V.MicrosoftAuthenticatorSoftwareOath -eq $true)
                    if ([bool]$Config.isSoftwareOathEnabled -ne $SoftwareOath) { $Drifts.Add("$($Method.Label): isSoftwareOathEnabled '$($Config.isSoftwareOathEnabled)' should be '$SoftwareOath'") }
                    $Params['MicrosoftAuthenticatorSoftwareOathEnabled'] = $SoftwareOath
                    foreach ($Feature in @(
                            @{ Setting = 'MicrosoftAuthenticatorDisplayAppInfo'; Property = 'displayAppInformationRequiredState'; Param = 'MicrosoftAuthenticatorDisplayAppInfo'; Label = 'Display App Info' }
                            @{ Setting = 'MicrosoftAuthenticatorDisplayLocation'; Property = 'displayLocationInformationRequiredState'; Param = 'MicrosoftAuthenticatorDisplayLocation'; Label = 'Display Location' }
                            @{ Setting = 'MicrosoftAuthenticatorCompanionApp'; Property = 'companionAppAllowedState'; Param = 'MicrosoftAuthenticatorCompanionApp'; Label = 'Companion App' }
                        )) {
                        $Desired = "$($V."$($Feature.Setting)".value ?? $V."$($Feature.Setting)")"
                        if (-not [string]::IsNullOrWhiteSpace($Desired)) {
                            $CurrentFeature = "$($Config.featureSettings."$($Feature.Property)".state)"
                            if ($CurrentFeature -ne $Desired) { $Drifts.Add("$($Method.Label): $($Feature.Label) '$CurrentFeature' should be '$Desired'") }
                            $Params[$Feature.Param] = $Desired
                        }
                    }
                }
            }
            'TemporaryAccessPass' {
                if ($Method.Enabled) {
                    # '' survives ?? - a blank lifetime graded AND wrote 0, which Graph
                    # rejects ("Accesspass minimum lifetime should be greater or equal to
                    # 10", proven live). Blank means the default, not zero.
                    $IntOrDefault = { param($Value, $Default) $Raw = "$($Value.value ?? $Value)"; if ([string]::IsNullOrWhiteSpace($Raw)) { [int]$Default } else { [int]$Raw } }
                    $UsableOnceRaw = "$($V.TAPUsableOnce.value ?? $V.TAPUsableOnce)"
                    $UsableOnce = [System.Convert]::ToBoolean("$(if ([string]::IsNullOrWhiteSpace($UsableOnceRaw)) { 'true' } else { $UsableOnceRaw })")
                    $DefaultLifetime = & $IntOrDefault $V.TAPDefaultLifetime 60
                    $MinLifetime = & $IntOrDefault $V.TAPMinLifetime 60
                    $MaxLifetime = & $IntOrDefault $V.TAPMaxLifetime 480
                    $DefaultLength = & $IntOrDefault $V.TAPDefaultLength 8
                    if ([System.Convert]::ToBoolean("$($Config.isUsableOnce)") -ne $UsableOnce) { $Drifts.Add("$($Method.Label): isUsableOnce should be '$UsableOnce'") }
                    if ([int]"$($Config.defaultLifetimeInMinutes)" -ne $DefaultLifetime) { $Drifts.Add("$($Method.Label): defaultLifetimeInMinutes '$($Config.defaultLifetimeInMinutes)' should be '$DefaultLifetime'") }
                    if ([int]"$($Config.minimumLifetimeInMinutes)" -ne $MinLifetime) { $Drifts.Add("$($Method.Label): minimumLifetimeInMinutes '$($Config.minimumLifetimeInMinutes)' should be '$MinLifetime'") }
                    if ([int]"$($Config.maximumLifetimeInMinutes)" -ne $MaxLifetime) { $Drifts.Add("$($Method.Label): maximumLifetimeInMinutes '$($Config.maximumLifetimeInMinutes)' should be '$MaxLifetime'") }
                    if ([int]"$($Config.defaultLength)" -ne $DefaultLength) { $Drifts.Add("$($Method.Label): defaultLength '$($Config.defaultLength)' should be '$DefaultLength'") }
                    $Params['TAPisUsableOnce'] = $UsableOnce
                    $Params['TAPDefaultLifeTime'] = $DefaultLifetime
                    $Params['TAPMinimumLifetime'] = $MinLifetime
                    $Params['TAPMaximumLifetime'] = $MaxLifetime
                    $Params['TAPDefaultLength'] = $DefaultLength
                }
            }
            'QRCodePin' {
                if ($Method.Enabled) {
                    # Same '' trap as TAP: blank grades/writes 0 and the helper's
                    # ValidateRange refuses it before Graph even sees the write.
                    $IntOrDefault = { param($Value, $Default) $Raw = "$($Value.value ?? $Value)"; if ([string]::IsNullOrWhiteSpace($Raw)) { [int]$Default } else { [int]$Raw } }
                    $Lifetime = & $IntOrDefault $V.QRCodeLifetimeInDays 365
                    $PinLength = & $IntOrDefault $V.QRCodePinLength 8
                    if ([int]"$($Config.standardQRCodeLifetimeInDays)" -ne $Lifetime) { $Drifts.Add("$($Method.Label): standardQRCodeLifetimeInDays should be '$Lifetime'") }
                    if ([int]"$($Config.pinLength)" -ne $PinLength) { $Drifts.Add("$($Method.Label): pinLength should be '$PinLength'") }
                    $Params['QRCodeLifetimeInDays'] = $Lifetime
                    $Params['QRCodePinLength'] = $PinLength
                }
            }
            'Email' {
                if ($Method.Enabled) {
                    $ExternalOtp = "$($V.EmailAllowExternalIdToUseEmailOtp.value ?? $V.EmailAllowExternalIdToUseEmailOtp)"
                    if (-not [string]::IsNullOrWhiteSpace($ExternalOtp)) {
                        if ("$($Config.allowExternalIdToUseEmailOtp)" -ne $ExternalOtp) { $Drifts.Add("$($Method.Label): allowExternalIdToUseEmailOtp should be '$ExternalOtp'") }
                        $Params['EmailAllowExternalIdToUseEmailOtp'] = $ExternalOtp
                    }
                    if (-not [string]::IsNullOrWhiteSpace($Method.ExcludeGroupName)) {
                        $ExcludeIds = & $ResolveGroup $Method.ExcludeGroupName
                        if ($ExcludeIds) {
                            $CurrentExcludeIds = @($Config.excludeTargets | ForEach-Object { "$($_.id)" })
                            $Diff = Compare-Object -ReferenceObject @($ExcludeIds | Sort-Object) -DifferenceObject @($CurrentExcludeIds | Sort-Object) -ErrorAction SilentlyContinue
                            if ($Diff) { $Drifts.Add("$($Method.Label): excludeTargets [$($CurrentExcludeIds -join ', ')] should be [$($ExcludeIds -join ', ')]") }
                            $Params['EmailExcludeGroupIds'] = @($ExcludeIds)
                        }
                    }
                }
            }
        }

        if ($Drifts.Count -gt 0) {
            foreach ($Drift in $Drifts) { $AllDrifts.Add($Drift) }
            $RemediationSets.Add([PSCustomObject]@{ Label = $Method.Label; Params = $Params })
        }
    }

    $Current = [PSCustomObject]@{ methodsOutOfPolicy = @($AllDrifts | Sort-Object) }
    # Carried for the executor: one Set-CIPPAuthenticationPolicy parameter set per drifted method.
    $Current | Add-Member -NotePropertyName 'remediationSets' -NotePropertyValue @($RemediationSets)

    @{
        Expected = [PSCustomObject]@{ methodsOutOfPolicy = @() }
        Current  = $Current
    }
}
