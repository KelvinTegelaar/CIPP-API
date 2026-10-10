function Test-CIPPCAGapCredentialRegistration {
    <#
    .SYNOPSIS
        Reviews policies that target "Register security info" for constraints that block new-device
        credential setup.
    .DESCRIPTION
        Since July 2026 (MC1326253) policies scoped to the register-security-info user action are evaluated
        during Windows Hello for Business and macOS Platform SSO registration.
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
    $RegisterSecurityInfo = "$($Reference.registerSecurityInfoAction)"
    $LegacyTrustedIps = "$($Reference.legacyMfaTrustedIpsLocation)"

    foreach ($Policy in @($Context.Policies)) {
        if ($Policy.state -eq 'disabled') { continue }
        if (-not (@($Policy.conditions.applications.includeUserActions) -contains $RegisterSecurityInfo)) { continue }

        $Grant = $Policy.grantControls
        $Controls = @($Grant.builtInControls)
        $Conditions = $Policy.conditions
        $Locations = $Conditions.locations

        $RequiresCompliance = ($Controls -contains 'compliantDevice') -or ($Controls -contains 'domainJoinedDevice')
        $RequiresApprovedApp = $Controls -contains 'approvedApplication'
        $RequiresAppProtection = $Controls -contains 'compliantApplication'
        $IncludedLocations = if ($null -ne $Locations) { @($Locations.includeLocations) } else { @() }
        $ExcludedLocations = if ($null -ne $Locations) { @($Locations.excludeLocations) } else { @() }
        $HasLocationConditions = ($IncludedLocations.Count -gt 0) -or ($ExcludedLocations.Count -gt 0)
        $HasDeviceFilter = $null -ne $Conditions.devices.deviceFilter.rule
        $HasMfaAlternative = ($Grant.operator -eq 'OR') -and (($Controls -contains 'mfa') -or ($null -ne $Grant.authenticationStrength))

        $Issues = [System.Collections.Generic.List[string]]::new()
        if ($RequiresCompliance -and -not $HasMfaAlternative) {
            $Issues.Add('A managed-device requirement, which a device cannot meet while it is still being set up')
        }
        if (($RequiresApprovedApp -or $RequiresAppProtection) -and -not $HasMfaAlternative) {
            $Issues.Add('An approved or protected app requirement, which may not be met before those apps are installed')
        }
        if ($HasLocationConditions) {
            if ($IncludedLocations.Count -gt 0 -and -not ($IncludedLocations -contains 'All') -and -not ($IncludedLocations -contains 'AllTrusted')) {
                $LocationNames = @($IncludedLocations | ForEach-Object {
                        if ($_ -eq $LegacyTrustedIps) { 'MFA Trusted IPs (legacy)' }
                        else {
                            $Named = $Context.NamedLocationById["$_"]
                            if ($Named.displayName) { "$($Named.displayName)" } else { "$_" }
                        }
                    }) -join ', '
                $Issues.Add("A network requirement limiting setup to $LocationNames, which blocks people setting up a device from home or on the road")
            }
            if (($ExcludedLocations -contains 'AllTrusted') -and -not ($IncludedLocations -contains 'AllTrusted')) {
                $Issues.Add('A block on untrusted networks, which affects people setting up a device from home or a public network')
            }
        }
        if ($HasDeviceFilter) {
            $Issues.Add('A device filter, which may not evaluate reliably before the device is fully registered')
        }

        if ($Issues.Count -eq 0) {
            $StateNote = if ($Policy.state -eq 'enabledForReportingButNotEnforced') {
                'The policy is in report-only mode, so it will only apply during registration once it is enforced.'
            } else {
                'The policy is enforced, so it already applies during registration.'
            }
            $Params = @{
                Severity         = 'Info'
                Category         = 'Sign-in method registration'
                Title            = 'Sign-in method registration policy is compatible with new-device setup'
                Description      = "Policies that protect the registration of sign-in methods now also apply when people set up Windows Hello or macOS Platform SSO on a new device. This one asks only for multifactor authentication and has no device, network or app conditions, so it should not get in the way of setting up a new device. $StateNote"
                Remediation      = 'No change needed. Make sure people can meet the multifactor requirement on a brand-new device, for example with a Temporary Access Pass, and let the helpdesk know an extra prompt can appear during setup.'
                AffectedPolicies = @($Policy.displayName)
                DocumentationUrl = 'https://learn.microsoft.com/entra/identity/conditional-access/policy-all-users-security-info-registration'
            }
            $Findings.Add((New-CIPPCAGapFinding @Params))
            continue
        }

        $Severity = 'Medium'
        if (($RequiresCompliance -and -not $HasMfaAlternative) -or ($HasLocationConditions -and -not ($IncludedLocations -contains 'All'))) {
            $Severity = 'High'
        }

        $Remediation = if ($RequiresCompliance -and -not $HasMfaAlternative) {
            'Keep the managed-device requirement for ordinary sign-in but not for registering sign-in methods, and let new devices be set up with multifactor authentication or a Temporary Access Pass.'
        } elseif ($HasLocationConditions) {
            'Allow registration from any network, or at least from the networks people actually set up devices on, and keep the stricter network rules for ordinary sign-in.'
        } else {
            'Confirm that people can meet the device and app conditions of this policy while setting up a new device, and relax them for the registration step if they cannot.'
        }

        $Params = @{
            Severity         = $Severity
            Category         = 'Sign-in method registration'
            Title            = 'Policy may stop people from setting up a new device'
            Description      = "Policies that protect the registration of sign-in methods also apply when people set up Windows Hello or macOS Platform SSO on a new device. This one has conditions a brand-new device may not be able to meet:`n$(@($Issues | ForEach-Object { "- $_" }) -join "`n")`n`nPeople setting up a new laptop or Mac could be unable to finish, and the helpdesk would see failed enrollments."
            Remediation      = $Remediation
            AffectedPolicies = @($Policy.displayName)
            DocumentationUrl = 'https://learn.microsoft.com/entra/identity/conditional-access/policy-all-users-security-info-registration'
        }
        $Findings.Add((New-CIPPCAGapFinding @Params))
    }

    @($Findings)
}
