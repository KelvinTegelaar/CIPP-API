function Test-CIPPCAGapMicrosoftGuidance {
    <#
    .SYNOPSIS
        Checks every policy against Microsoft's published guidance on Conditional Access side effects.
    .DESCRIPTION
        Each entry in Config/SecuritySimulations/CAAnalysis/MicrosoftGuidance.json describes a policy shape
        that Microsoft documents as breaking something (meeting-room devices, token protection scope,
        emergency access, retired grant controls and so on). A policy that matches produces one finding
        with the guidance text, its severity and the Microsoft documentation link.
    .FUNCTIONALITY
        Internal
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        $Context,
        [switch]$IncludeAdvisory
    )

    $Findings = [System.Collections.Generic.List[object]]::new()
    $Reference = $Context.Data.Reference
    $Apps = $Reference.guidanceAppIds
    $GuidanceById = @{}
    foreach ($Guidance in @($Context.Data.MicrosoftGuidance)) { $GuidanceById["$($Guidance.id)"] = $Guidance }

    $ExchangeOnline = "$($Apps.exchangeOnline)".ToLowerInvariant()
    $SharePointOnline = "$($Apps.sharePointOnline)".ToLowerInvariant()
    $TeamsService = "$($Apps.teamsService)".ToLowerInvariant()
    $Office365Group = "$($Apps.office365Group)".ToLowerInvariant()
    $DefenderAtp = "$($Apps.defenderAtpXplat)".ToLowerInvariant()
    $DefenderTvm = "$($Apps.defenderTvm)".ToLowerInvariant()
    $WindowsCloudLogin = "$($Apps.windowsCloudLogin)".ToLowerInvariant()
    $TokenProtectionSupported = @($ExchangeOnline, $SharePointOnline, $TeamsService, "$($Apps.azureVirtualDesktop)".ToLowerInvariant(), "$($Apps.windows365)".ToLowerInvariant(), $WindowsCloudLogin)
    $DirSyncRoleId = "$($Reference.directorySyncRoleTemplateId)"

    $IsActive = { param($P) $P.state -in @('enabled', 'enabledForReportingButNotEnforced') }
    $TargetsAllUsers = { param($P) @($P.conditions.users.includeUsers) -contains 'All' }
    $TargetsAllApps = { param($P) @($P.conditions.applications.includeApplications) -contains 'All' }
    $HasMfaGrant = { param($P) (@($P.grantControls.builtInControls) -contains 'mfa') -or ($null -ne $P.grantControls.authenticationStrength) }
    $HasBlockGrant = { param($P) @($P.grantControls.builtInControls) -contains 'block' }
    $HasComplianceGrant = { param($P) @($P.grantControls.builtInControls) -contains 'compliantDevice' }
    $HasAdminRoles = { param($P) @($P.conditions.users.includeRoles).Count -gt 0 }
    $HasNoUserExclusions = { param($P) $U = $P.conditions.users; (@($U.excludeUsers).Count -eq 0) -and (@($U.excludeGroups).Count -eq 0) -and (@($U.excludeRoles).Count -eq 0) }
    $HasTokenProtection = {
        param($P)
        $Session = $P.sessionControls
        if ($null -eq $Session) { return $false }
        if ($Session.secureSignInSession.isEnabled -eq $true) { return $true }
        if ($Session.tokenProtection.signInSessionTokenProtection.isEnabled -eq $true) { return $true }
        $false
    }
    $LowerApps = { param($Values) , [string[]]@(@($Values) | ForEach-Object { "$_".ToLowerInvariant() }) }

    $Results = [System.Collections.Generic.List[object]]::new()
    $AddResult = {
        param($GuidanceId, $Policy, $Detail, $Impacted)
        $Guidance = $GuidanceById[$GuidanceId]
        if ($null -eq $Guidance) { return }
        $Results.Add([PSCustomObject]@{
                guidanceId        = $GuidanceId
                policyId          = $Policy.id
                policyName        = $Policy.displayName
                severity          = "$($Guidance.severity)"
                title             = "$($Guidance.title)"
                detail            = $Detail
                impactedResources = [string[]]@($Impacted | Where-Object { $_ })
                remediation       = "$($Guidance.remediation)"
                docUrl            = "$($Guidance.docUrl)"
            })
    }

    foreach ($Policy in @($Context.Policies)) {
        $Active = & $IsActive $Policy
        $AllUsers = & $TargetsAllUsers $Policy
        $AllApps = & $TargetsAllApps $Policy
        $Grant = $Policy.grantControls
        $Controls = @($Grant.builtInControls)
        $IncludeApps = & $LowerApps $Policy.conditions.applications.includeApplications
        $ExcludeApps = & $LowerApps $Policy.conditions.applications.excludeApplications
        $Session = $Policy.sessionControls
        $SignInFrequency = $Session.signInFrequency
        $TokenProtection = & $HasTokenProtection $Policy

        if ($Active -and $TokenProtection) {
            if ($IncludeApps -contains 'all') {
                & $AddResult 'TokenProtectionApps' $Policy 'This token-protection policy applies to every application, although only a few Microsoft services support the feature. People using unsupported tools such as Power Query, developer extensions and older Office installations will be blocked.' @('PowerShell modules accessing SharePoint', 'PowerQuery extension for Excel', 'VS Code extensions accessing Exchange/SharePoint', 'Office perpetual clients')
            } elseif ($IncludeApps -contains $Office365Group) {
                & $AddResult 'TokenProtectionApps' $Policy 'This token-protection policy applies to the Office 365 application group as a whole, which Microsoft warns can cause unexpected failures because not every service in the group supports the feature.' @('Office 365 application group members')
            } else {
                $Unsupported = @($IncludeApps | Where-Object { $TokenProtectionSupported -notcontains $_ })
                if ($Unsupported.Count -gt 0) {
                    & $AddResult 'TokenProtectionApps' $Policy "This token-protection policy applies to $($Unsupported.Count) application(s) that may not support the feature; only Exchange Online, SharePoint Online, Teams, Azure Virtual Desktop, Windows 365 and Windows Cloud Login do." $Unsupported
                }
            }
        }

        if ($Active -and $TokenProtection) {
            $Issues = [System.Collections.Generic.List[string]]::new()
            $Platforms = $Policy.conditions.platforms
            if ($null -eq $Platforms -or -not (@($Platforms.includePlatforms) -contains 'windows')) {
                $Issues.Add('The policy is not limited to Windows devices, although token protection only works there.')
            }
            $ClientTypes = @($Policy.conditions.clientAppTypes)
            if ($ClientTypes.Count -eq 0 -or ($ClientTypes -contains 'browser')) {
                $Issues.Add('The policy also applies to web browsers, which do not support token protection, so browser-based tools such as Teams on the web will be blocked.')
            }
            if ($Issues.Count -gt 0) {
                & $AddResult 'TokenProtectionPlatforms' $Policy ($Issues -join ' ') @('macOS / iOS / Android / Linux users', 'Teams Web (MSAL.js)', 'Browser-based applications')
            }
        }

        if ($Active -and $TokenProtection) {
            $DeviceFilter = $Policy.conditions.devices.deviceFilter
            if ($null -eq $DeviceFilter) {
                & $AddResult 'TokenProtectionDevices' $Policy 'This token-protection policy does not exempt the device types that cannot support it. Meeting-room devices, Cloud PCs, virtual desktop hosts, self-deploying and bulk-enrolled devices and Azure virtual machines will be blocked with unclear error messages.' @('Surface Hub', 'Teams Rooms (MTR) on Windows', 'Cloud PCs (Microsoft Entra joined)', 'Azure Virtual Desktop session hosts (Microsoft Entra joined)', 'Windows Autopilot self-deploying devices', 'Bulk-enrolled Windows devices', 'Azure VMs with Entra ID auth')
            } else {
                $Rule = "$($DeviceFilter.rule)".ToLowerInvariant()
                $Missing = @($Reference.tokenProtectionDeviceFilterPatterns | Where-Object { -not $Rule.Contains("$($_.pattern)") })
                if ($Missing.Count -gt 0 -and "$($DeviceFilter.mode)" -eq 'exclude') {
                    $MissingLabels = @($Missing | ForEach-Object { "$($_.label)" })
                    & $AddResult 'TokenProtectionDevices' $Policy "The device filter on this token-protection policy may not exempt every device type that cannot support it; possibly missing: $($MissingLabels -join ', ')." $MissingLabels
                }
            }
        }

        if ($Active -and $AllUsers -and ((& $HasMfaGrant $Policy) -or (& $HasBlockGrant $Policy) -or (& $HasComplianceGrant $Policy)) -and (& $HasNoUserExclusions $Policy)) {
            & $AddResult 'BreakGlassMissing' $Policy "$($Policy.displayName) applies to every user and exempts nobody. A mistake in the policy or a service outage would lock out everyone, administrators included, with no account left to recover access." @('All administrators', 'Emergency access accounts')
        }

        if ($Active -and $AllUsers -and $AllApps -and $Grant.present) {
            $UnsupportedControls = @($Controls | Where-Object { $_ -in @('mfa', 'compliantDevice', 'domainJoinedDevice', 'approvedApplication', 'compliantApplication', 'passwordChange') })
            $HasStrength = $null -ne $Grant.authenticationStrength
            if ($UnsupportedControls.Count -gt 0 -or $HasStrength) {
                $ControlList = [System.Collections.Generic.List[string]]::new()
                foreach ($ControlName in $UnsupportedControls) { $ControlList.Add($ControlName) }
                if ($HasStrength) { $ControlList.Add('authentication strength') }
                & $AddResult 'SurfaceHubMfa' $Policy "This policy requires $($ControlList -join ', ') from every user. Surface Hub meeting-room accounts cannot meet such requirements and will fail to sign in, which breaks room calendars and meetings." @('Surface Hub calendar sync', 'Surface Hub Teams meetings', 'Surface Hub collaborative whiteboard')
            }
        }

        if ($Active -and $AllUsers -and $Grant.present -and (($Controls -contains 'mfa') -or ($null -ne $Grant.authenticationStrength)) -and $AllApps) {
            & $AddResult 'TeamsRoomsMfa' $Policy 'This policy requires multifactor authentication from every user for every application. Teams Rooms devices on Windows cannot perform it, and Android room devices cannot meet an authentication strength, so meeting-room accounts will be unable to sign in.' @('Teams Rooms on Windows', 'Teams Rooms on Android (auth strength only)', 'Teams Panels')
        }

        if ($Active -and (& $HasBlockGrant $Policy) -and -not [string]::IsNullOrWhiteSpace("$($Policy.conditions.authenticationFlows.transferMethods)")) {
            & $AddResult 'DeviceCodeTeamsDevices' $Policy 'This policy blocks the device-code sign-in flow for everyone. Teams phones, panels and Android room devices rely on that flow for their initial setup and can no longer be signed in remotely.' @('Teams Rooms on Android', 'Teams phones', 'Teams panels', 'Remote device sign-in scenarios')
        }

        if ($Active -and $AllUsers -and $SignInFrequency.isEnabled -eq $true -and $AllApps) {
            & $AddResult 'SignInFrequencyTeamsRooms' $Policy "This policy makes every user sign in again every $($SignInFrequency.value) $($SignInFrequency.type). Teams Rooms, phones and panels cannot handle that and will periodically sign out, disrupting scheduled meetings." @('Teams Rooms on Windows', 'Teams Rooms on Android', 'Teams phones', 'Teams panels')
        }

        if ($Active -and $AllUsers -and $AllApps) {
            $Locations = $Policy.conditions.locations
            $IsRestrictive = (& $HasBlockGrant $Policy) -or (($null -ne $Locations) -and (@($Locations.includeLocations).Count -gt 0) -and (& $HasBlockGrant $Policy))
            if ($IsRestrictive -and -not (($ExcludeApps -contains $DefenderAtp) -and ($ExcludeApps -contains $DefenderTvm))) {
                & $AddResult 'DefenderMobileApps' $Policy 'This blocking policy covers every application without exempting the Microsoft Defender mobile apps. Defender may then be unable to report device health, and devices can be marked non-compliant simply because the report never arrives.' @("MicrosoftDefenderATP XPlat ($DefenderAtp)", "Microsoft Defender for Mobile TVM ($DefenderTvm)", 'Mobile device compliance reporting')
            }
        }

        if ($Active -and $AllUsers -and $AllApps -and ((& $HasMfaGrant $Policy) -or (& $HasComplianceGrant $Policy)) -and -not ($ExcludeApps -contains $WindowsCloudLogin)) {
            & $AddResult 'AzureVmSignInMfa' $Policy 'This policy requires multifactor authentication or a managed device from every user for every application, without exempting sign-ins to Azure virtual machines. Remote desktop connections to those machines can only meet the requirement from a device that supports Windows Hello for Business, and Windows Server devices can never count as compliant, so administrators may be unable to connect.' @("Microsoft Azure Windows Virtual Machine Sign-In ($WindowsCloudLogin)", 'RDP connections to Azure VMs', 'RDP connections to Arc-enabled Windows Servers', 'Windows Server RDP client devices (device compliance unsupported)')
        }

        if ($Active -and "$($Session.continuousAccessEvaluation.mode)" -eq 'disabled') {
            & $AddResult 'ContinuousAccessEvaluationDisabled' $Policy 'This policy switches off continuous access evaluation. After a security event such as an account being disabled or a password change, existing sessions stay valid for up to an hour instead of being cut off immediately.' @('Real-time user session revocation', 'Location-based policy enforcement', 'Risk-based session termination')
        }

        if ($Active -and $SignInFrequency.isEnabled -eq $true -and -not ($IncludeApps -contains 'all')) {
            $TargetsIndividualM365 = @($IncludeApps | Where-Object { $_ -in @($ExchangeOnline, $SharePointOnline, $TeamsService) }).Count -gt 0
            if ($TargetsIndividualM365) {
                & $AddResult 'SignInFrequencyIndividualServices' $Policy 'This policy applies a sign-in frequency to individual Microsoft 365 services rather than to all applications. Microsoft does not support that arrangement because it can interrupt or stop the Teams device sign-in flow.' @('Teams sign-in flow', 'Teams Rooms devices', 'Teams desktop/mobile clients')
            }
        }

        if ($Active -and $Session.disableResilienceDefaults -eq $true) {
            $Scope = if ($AllUsers) { 'all users' } else { 'the users it targets' }
            & $AddResult 'ResilienceDefaultsDisabled' $Policy "This policy turns off resilience defaults for $Scope. During a Microsoft sign-in service outage, anyone whose session expires loses access until the service recovers, which can stop work for hours." @('All users covered by this policy during Entra ID outages', 'Business continuity during identity service disruptions')
        }

        if ($Active -and $AllApps -and $ExcludeApps.Count -gt 0) {
            & $AddResult 'AllResourcesAppExclusion' $Policy 'This policy covers every application but exempts some. Microsoft now enforces basic profile and directory permissions through the directory service itself, so without a policy that covers that service, applications that only ask for basic details may be challenged unexpectedly or may still slip past enforcement depending on rollout.' @('Windows Azure Active Directory (00000002-0000-0000-c000-000000000000)', 'Apps requesting User.Read, openid, profile, email, offline_access scopes', 'Native clients and SPAs with basic Azure AD Graph access')
        }

        if ($Active -and $AllUsers -and (& $HasMfaGrant $Policy) -and $DirSyncRoleId -and (@($Policy.conditions.users.excludeRoles) -contains $DirSyncRoleId)) {
            & $AddResult 'DirectorySyncAccountMfa' $Policy 'This multifactor policy exempts the directory synchronization role. Recent versions of Entra Connect let the synchronization service authenticate as an application rather than a user account, which removes the need for this exemption and the gap it leaves.' @('Directory Synchronization Accounts role', 'Entra Connect sync service account', 'Hybrid identity sync pipeline')
        }

        if ($Active -and ($AllUsers -or (& $HasAdminRoles $Policy))) {
            $HasCustomFactors = @($Grant.customAuthenticationFactors).Count -gt 0
            $HasEamViaStrength = $false
            $StrengthName = ''
            $ExternalMethods = @()
            $StrengthRef = $Grant.authenticationStrength
            if ($StrengthRef.id -and $Context.AuthStrengths.ContainsKey("$($StrengthRef.id)")) {
                $Resolved = $Context.AuthStrengths["$($StrengthRef.id)"]
                $ExternalMethods = @($Resolved.allowedCombinations | Where-Object { "$_".ToLowerInvariant().Contains('externalauthenticationmethod') })
                if ($ExternalMethods.Count -gt 0) {
                    $HasEamViaStrength = $true
                    $StrengthName = if ($Resolved.displayName) { "$($Resolved.displayName)" } elseif ($StrengthRef.displayName) { "$($StrengthRef.displayName)" } else { 'Unknown' }
                }
            }
            if ($HasCustomFactors -or $HasEamViaStrength) {
                $ExcludeGuestObject = $Policy.conditions.users.excludeGuestsOrExternalUsers
                $ExcludesGuests = ($null -ne $ExcludeGuestObject) -and (@($ExcludeGuestObject.PSObject.Properties).Count -gt 0)
                $EamSource = if ($HasEamViaStrength) { "the ""$StrengthName"" authentication strength, which relies on an external authentication provider" } else { 'a legacy custom control from an external authentication provider' }
                $Detail = if ($ExcludesGuests) {
                    "This policy relies on $EamSource. Guests appear to be exempt, but partner, service-provider and cross-tenant synchronization accounts may still be caught if the exemption does not cover every type of external identity."
                } else {
                    "This policy relies on $EamSource and applies to guests and external users as well. They are not enrolled with your external provider and cannot be, so they will be blocked even though Microsoft's own multifactor authentication would have been enough."
                }
                $Impacted = [System.Collections.Generic.List[string]]::new()
                foreach ($Item in @('B2B guest users', 'External service providers and vendors', 'Cross-tenant collaboration partners', 'Managed service provider (MSP) accounts')) { $Impacted.Add($Item) }
                if ($ExcludesGuests) { $Impacted.Add('Verify: B2B direct connect and cross-tenant sync accounts') }
                if ($HasEamViaStrength) { $Impacted.Add("Auth Strength: ""$StrengthName"" - $($ExternalMethods.Count) external method combination(s)") }
                & $AddResult 'ExternalAuthMethodGuests' $Policy $Detail @($Impacted)
            }
        }

        if ($Controls -contains 'approvedApplication') {
            $HasAppProtection = $Controls -contains 'compliantApplication'
            if ($HasAppProtection -and $Grant.operator -eq 'OR') {
            } elseif ($HasAppProtection -and $Grant.operator -eq 'AND') {
                & $AddResult 'ApprovedClientAppRetirement' $Policy "$($Policy.displayName) requires both an approved client app and an app protection policy together. Microsoft is retiring the approved-client-app requirement, after which the app protection policy alone must be enough for this policy to keep working." @('Mobile device users on iOS and Android', 'Users accessing M365 apps from mobile devices')
            } else {
                & $AddResult 'ApprovedClientAppRetirement' $Policy "$($Policy.displayName) relies only on the approved-client-app requirement, which Microsoft is retiring. Once it stops being enforced, this policy no longer protects data in mobile apps." @('Mobile device users on iOS and Android', 'Users accessing M365 apps from mobile devices', 'Unmanaged BYOD devices')
            }
        }

        if ($Active -and @($Policy.conditions.userRiskLevels).Count -gt 0 -and $Grant.present -and ($Controls -contains 'passwordChange')) {
            $UsesRiskRemediation = $Controls -contains 'riskRemediation'
            $Tail = if ($UsesRiskRemediation) { 'The policy already includes the newer risk-remediation requirement, so the password-change requirement can simply be removed.' } else { 'The newer risk-remediation requirement supports every sign-in method.' }
            & $AddResult 'UserRiskPasswordChangeRetired' $Policy "$($Policy.displayName) responds to a risky user by demanding a password change, a requirement Microsoft has retired. People who sign in without a password cannot complete it and stay blocked once flagged. $Tail" @('Passwordless users (FIDO2, Windows Hello for Business)', 'External Authentication Method users (Duo, Okta, etc.)', 'High-risk users who cannot complete a password change flow')
        }

        if ($Active -and @($Policy.conditions.userRiskLevels).Count -gt 0 -and $Grant.present -and ($Controls -contains 'riskRemediation') -and ($null -ne $Grant.authenticationStrength)) {
            $ScopeNote = 'Whether this tenant uses an external authentication provider could not be verified, so this finding is shown as a precaution and may not apply.'
            & $AddResult 'UserRiskRemediationExternalProvider' $Policy "$($Policy.displayName) asks risky users to remediate through an authentication strength. Authentication strengths cannot accept external providers such as Duo, Okta or Ping, so people who rely on one stay blocked once flagged unless a companion policy lets them remediate with plain multifactor authentication. $ScopeNote" @('Users enrolled in External Authentication Methods (Duo, Okta Verify, Ping, etc.)', 'Any tenant using a third-party MFA provider as EAM', 'High-risk EAM users who cannot complete authentication strength challenges')
        }
    }

    $TemplateByGuidance = @{
        'AllResourcesAppExclusion'         = "$($Reference.templates.windowsAzureAdBaselineScopes)"
        'UserRiskPasswordChangeRetired'   = "$($Reference.templates.riskRemediationHigh)"
        'UserRiskRemediationExternalProvider' = "$($Reference.templates.riskRemediationEam)"
        'ApprovedClientAppRetirement'         = "$($Reference.templates.appProtectionMobile)"
    }

    foreach ($Result in $Results) {
        if ($Result.guidanceId -eq 'AllResourcesAppExclusion' -and -not $IncludeAdvisory.IsPresent) { continue }
        $IsPromoted = $Result.severity -in @('critical', 'high')
        if (-not $IsPromoted -and -not $IncludeAdvisory.IsPresent) { continue }
        $SeverityLabel = switch ($Result.severity) {
            'critical' { 'Critical' }
            'high' { 'High' }
            'medium' { 'Medium' }
            default { 'Info' }
        }
        $Params = @{
            Severity         = $SeverityLabel
            Category         = 'Microsoft guidance'
            Title            = $Result.title
            Description      = "$($Result.detail)"
            Remediation      = $Result.remediation
            AffectedPolicies = @($Result.policyName)
            RelatedIds       = @($Result.impactedResources)
            DocumentationUrl = $Result.docUrl
        }
        if ($TemplateByGuidance.ContainsKey($Result.guidanceId)) { $Params['CaTemplate'] = $TemplateByGuidance[$Result.guidanceId] }
        $Findings.Add((New-CIPPCAGapFinding @Params))
    }

    @($Findings)
}
