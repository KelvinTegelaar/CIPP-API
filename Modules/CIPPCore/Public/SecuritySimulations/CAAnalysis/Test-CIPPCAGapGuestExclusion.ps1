function Test-CIPPCAGapGuestExclusion {
    <#
    .SYNOPSIS
        Flags All-users policies that exclude guest or external users, and tenants with no guest coverage at
        all.
    .DESCRIPTION
        Per policy (any state): a policy targeting All users that excludes GuestsOrExternalUsers, either the
        simple sentinel or the structured excludeGuestsOrExternalUsers object, produces a finding whose
        severity depends on what the policy enforces (security-info registration, block, MFA on all apps, or
        other) and on whether another non-disabled policy covers guests.
    .FUNCTIONALITY
        Internal
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        $Context
    )

    $Findings = [System.Collections.Generic.List[object]]::new()
    $Reference = $Context.Data.Reference
    $TypeLabels = $Reference.guestTypeLabels
    $AllKnownTypes = @($Reference.guestTypeOrder | ForEach-Object { "$_" })
    $RegisterSecurityInfo = "$($Reference.registerSecurityInfoAction)"

    $LabelOf = {
        param($TypeName)
        $Label = $TypeLabels.$TypeName
        if ($Label) { "$Label" } else { "$TypeName" }
    }

    foreach ($Policy in @($Context.Policies)) {
        $Users = $Policy.conditions.users
        if (-not (@($Users.includeUsers) -contains 'All')) { continue }

        $ExcludesGuestsSimple = @($Users.excludeUsers) -contains 'GuestsOrExternalUsers'
        $ExcludeObject = $Users.excludeGuestsOrExternalUsers
        $HasStructuredExclusion = ($null -ne $ExcludeObject) -and ($null -ne $ExcludeObject.guestOrExternalUserTypes)
        if (-not $ExcludesGuestsSimple -and -not $HasStructuredExclusion) { continue }

        $ExcludedGuestTypes = @()
        $ExternalTenantScope = ''
        if ($HasStructuredExclusion) {
            $ExcludedGuestTypes = @("$($ExcludeObject.guestOrExternalUserTypes)" -split ',' | ForEach-Object { $_.Trim() } | Where-Object { $_ })
            $Tenants = $ExcludeObject.externalTenants
            if ("$($Tenants.'@odata.type')".Contains('AllExternalTenants') -or "$($Tenants.membershipKind)" -eq 'all') {
                $ExternalTenantScope = 'all external organizations'
            } elseif ("$($Tenants.membershipKind)" -eq 'enumerated') {
                $ExternalTenantScope = 'specific external organizations'
            }
        }

        $ExcludesAllTypes = $ExcludesGuestsSimple -or (@($AllKnownTypes | Where-Object { $ExcludedGuestTypes -notcontains $_ }).Count -eq 0)

        $Controls = @($Policy.grantControls.builtInControls)
        $RequiresMfa = ($Controls -contains 'mfa') -or ($null -ne $Policy.grantControls.authenticationStrength)
        $Blocks = $Controls -contains 'block'
        $TargetsSecurityRegistration = @($Policy.conditions.applications.includeUserActions) -contains $RegisterSecurityInfo
        $TargetsAllApps = @($Policy.conditions.applications.includeApplications) -contains 'All'

        $HasGuestCoveragePolicy = $false
        foreach ($Other in @($Context.Policies)) {
            if ($Other.id -eq $Policy.id -or $Other.state -eq 'disabled') { continue }
            $OtherUsers = $Other.conditions.users
            $IncludesGuests = (@($OtherUsers.includeUsers) -contains 'GuestsOrExternalUsers') -or ($null -ne $OtherUsers.includeGuestsOrExternalUsers)
            $AllWithoutGuestExclusion = (@($OtherUsers.includeUsers) -contains 'All') -and -not (@($OtherUsers.excludeUsers) -contains 'GuestsOrExternalUsers') -and ($null -eq $OtherUsers.excludeGuestsOrExternalUsers)
            if ($IncludesGuests -or $AllWithoutGuestExclusion) { $HasGuestCoveragePolicy = $true; break }
        }

        if ($ExcludesGuestsSimple) {
            $GuestDescription = 'all guest and external users'
            $ExcludedTypesList = $AllKnownTypes
        } else {
            $GuestDescription = (@($ExcludedGuestTypes | ForEach-Object { & $LabelOf $_ }) -join ', ')
            if ($ExternalTenantScope) { $GuestDescription += " from $ExternalTenantScope" }
            $ExcludedTypesList = $ExcludedGuestTypes
        }

        $ResourceTenantEnforceable = @($ExcludedTypesList | Where-Object { $_ -in @('b2bCollaborationGuest', 'b2bCollaborationMember', 'internalGuest', 'serviceProvider') })
        $HomeTenantOnly = @($ExcludedTypesList | Where-Object { $_ -eq 'b2bDirectConnectUser' })
        $OtherTypes = @($ExcludedTypesList | Where-Object { $_ -eq 'otherExternalUser' })

        $EnforcementDetail = ''
        if ($ResourceTenantEnforceable.Count -gt 0) {
            $EnforcementDetail += "`n`nGuest types this tenant can hold to its own requirements: $(@($ResourceTenantEnforceable | ForEach-Object { & $LabelOf $_ }) -join ', '). They complete multifactor authentication in their home organization, and this tenant can be set to trust that result."
        }
        if ($HomeTenantOnly.Count -gt 0) {
            $EnforcementDetail += "`n`nGuest types that sign in only through their home organization: $(& $LabelOf 'b2bDirectConnectUser'). This tenant cannot enforce its own requirements on them and can only ask that their home organization applies equivalent ones."
        }
        if ($OtherTypes.Count -gt 0) {
            $EnforcementDetail += "`n`nOther external identities exempt here: $(& $LabelOf 'otherExternalUser'). These are external accounts that fall outside the standard guest and partner categories."
        }

        if ($TargetsSecurityRegistration) {
            $Severity = if ($HasGuestCoveragePolicy) { 'Medium' } else { 'High' }
            $ContextDetail = "This policy protects the registration of sign-in methods, yet $GuestDescription are exempt from it. A compromised guest account could add its own sign-in methods unchallenged."
        } elseif ($Blocks -and $TargetsAllApps) {
            $Severity = if ($HasGuestCoveragePolicy) { 'Medium' } else { 'High' }
            $ContextDetail = "This policy blocks access to every application, yet $GuestDescription are exempt from it and pass where everyone else is stopped."
        } elseif ($RequiresMfa -and $TargetsAllApps) {
            $Severity = if ($HasGuestCoveragePolicy) { 'Medium' } else { 'High' }
            $ContextDetail = "This policy requires multifactor authentication for every application, yet $GuestDescription are exempt from it and can sign in with a password alone."
        } else {
            $Severity = if ($HasGuestCoveragePolicy) { 'Low' } else { 'Medium' }
            $ContextDetail = "This policy applies to all users, yet $GuestDescription are exempt from it and its requirements do not reach them."
        }
        if (-not $HasGuestCoveragePolicy) {
            $ContextDetail += ' No other policy applies comparable requirements to guests, so they are left without this protection.'
        }

        $TypesText = if ($ExcludesGuestsSimple) {
            ' Exempt guest types: every type of guest and external user.'
        } elseif ($ExcludedGuestTypes.Count -gt 0) {
            " Exempt guest types: $(@($ExcludedGuestTypes | ForEach-Object { & $LabelOf $_ }) -join ', ')."
        } else { '' }
        $ScopeText = if ($ExternalTenantScope) { " This applies to guests from $ExternalTenantScope." } else { '' }

        $Remediation = if ($HasGuestCoveragePolicy) {
            'Confirm that the policy covering guests applies the same requirements to the same applications, and trust the multifactor authentication guests complete in their home organization so they can meet it.'
        } else {
            "Require multifactor authentication from guests through a dedicated policy such as ""$($Reference.templates.mfaB2BGuest)"" or ""$($Reference.templates.mfaMixedGuests)"", or remove the exemption from this policy, and trust the multifactor authentication guests complete in their home organization."
        }

        $TitleCount = if ($ExcludesAllTypes) { 'All' } else { "$($ExcludedGuestTypes.Count)" }
        $TitleSuffix = if ($HasGuestCoveragePolicy) { '' } else { ' with no other policy covering them' }

        $Params = @{
            Severity         = $Severity
            Category         = 'Guest coverage'
            Title            = "$TitleCount external user type(s) exempt from this policy$TitleSuffix"
            Description      = $ContextDetail + $TypesText + $ScopeText + $EnforcementDetail
            Remediation      = $Remediation
            AffectedPolicies = @($Policy.displayName)
            DocumentationUrl = 'https://learn.microsoft.com/entra/identity/conditional-access/policy-old-require-mfa-guest'
        }
        if (-not $HasGuestCoveragePolicy) { $Params['CaTemplate'] = "$($Reference.templates.mfaB2BGuest)" }
        $Findings.Add((New-CIPPCAGapFinding @Params))
    }

    $GuestExcludingPolicies = @($Context.Enabled | Where-Object {
            $U = $_.conditions.users
            if (-not (@($U.includeUsers) -contains 'All')) { return $false }
            (@($U.excludeUsers) -contains 'GuestsOrExternalUsers') -or ($null -ne $U.excludeGuestsOrExternalUsers -and $null -ne $U.excludeGuestsOrExternalUsers.guestOrExternalUserTypes)
        })
    $HasGuestSpecificMfa = @($Context.Enabled | Where-Object {
            $U = $_.conditions.users
            $IncludesGuests = (@($U.includeUsers) -contains 'GuestsOrExternalUsers') -or ($null -ne $U.includeGuestsOrExternalUsers)
            $RequiresMfa = (@($_.grantControls.builtInControls) -contains 'mfa') -or ($null -ne $_.grantControls.authenticationStrength)
            $IncludesGuests -and $RequiresMfa
        }).Count -gt 0
    $HasMfaForAll = @($Context.Enabled | Where-Object {
            (@($_.conditions.users.includeUsers) -contains 'All') -and ((@($_.grantControls.builtInControls) -contains 'mfa') -or ($null -ne $_.grantControls.authenticationStrength))
        }).Count -gt 0

    if ($GuestExcludingPolicies.Count -gt 0 -and -not $HasGuestSpecificMfa -and -not $HasMfaForAll) {
        $Names = @($GuestExcludingPolicies | ForEach-Object { $_.displayName })
        $Params = @{
            Severity         = 'High'
            Category         = 'Guest coverage'
            Title            = "Guests are exempt from $($GuestExcludingPolicies.Count) policy(ies) and face no multifactor requirement"
            Description      = "External accounts are a common way into a tenant, and here they can sign in with a password alone. The enforced policies that exempt them: $($Names -join ', ')."
            Remediation      = 'Require multifactor authentication from all guest and external users for every application, and consider a shorter session lifetime for them.'
            AffectedPolicies = $Names
            CaTemplate       = "$($Reference.templates.mfaGuests)"
            DocumentationUrl = 'https://learn.microsoft.com/entra/identity/conditional-access/policy-old-require-mfa-guest'
        }
        $Findings.Add((New-CIPPCAGapFinding @Params))
    }

    @($Findings)
}
