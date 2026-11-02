function Test-CIPPCAGapUserAgentBypass {
    <#
    .SYNOPSIS
        Detects platform- and client-type-specific MFA policies that can be bypassed by spoofing the user
        agent.
    .DESCRIPTION
        Per policy (non-disabled): an MFA or device-compliance policy scoped to specific device platforms
        can be bypassed by presenting an unrecognized platform; this is High unless an enabled tenant-wide
        policy blocks unknown platforms (then Info, naming the companion policy).
    .FUNCTIONALITY
        Internal
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        $Context
    )

    $Findings = [System.Collections.Generic.List[object]]::new()

    $IsBlockUnknownPlatformsPolicy = {
        param($P)
        $Platforms = $P.conditions.platforms
        ($P.state -eq 'enabled') -and
        ($null -ne $Platforms) -and
        (@($P.grantControls.builtInControls) -contains 'block') -and
        (@($Platforms.includePlatforms) -contains 'all') -and
        (@($Platforms.excludePlatforms).Count -gt 0) -and
        (@($P.conditions.users.includeUsers) -contains 'All') -and
        (@($P.conditions.applications.includeApplications) -contains 'All')
    }

    foreach ($Policy in @($Context.Policies)) {
        if ($Policy.state -eq 'disabled') { continue }

        $Platforms = $Policy.conditions.platforms
        $Controls = @($Policy.grantControls.builtInControls)
        $ClientAppTypes = @($Policy.conditions.clientAppTypes)
        $RequiresMfa = ($Controls -contains 'mfa') -or ($null -ne $Policy.grantControls.authenticationStrength)
        $RequiresCompliance = ($Controls -contains 'compliantDevice') -or ($Controls -contains 'domainJoinedDevice')

        if ($null -ne $Platforms -and @($Platforms.includePlatforms).Count -gt 0 -and -not (@($Platforms.includePlatforms) -contains 'all')) {
            $Targeted = @($Platforms.includePlatforms) -join ', '
            if ($RequiresMfa -or $RequiresCompliance) {
                $Companion = $null
                foreach ($Other in @($Context.Policies)) {
                    if ($Other.id -ne $Policy.id -and (& $IsBlockUnknownPlatformsPolicy $Other)) { $Companion = $Other; break }
                }
                if ($Companion) {
                    $Params = @{
                        Severity         = 'Info'
                        Category         = 'Platform coverage'
                        Title            = "Policy applies to $Targeted only, with unknown platforms blocked elsewhere"
                        Description      = "On its own, a policy limited to $Targeted could be sidestepped by a device that presents itself as an unrecognized platform. $($Companion.displayName) blocks such platforms across the tenant, which closes that route."
                        Remediation      = "No change needed for unknown platforms, which $($Companion.displayName) covers. Confirm that the recognized platforms this policy leaves out are covered by another policy."
                        AffectedPolicies = @($Policy.displayName, $Companion.displayName)
                        DocumentationUrl = 'https://learn.microsoft.com/entra/identity/conditional-access/policy-all-users-device-unknown-unsupported'
                    }
                } else {
                    $Params = @{
                        Severity         = 'High'
                        Category         = 'Platform coverage'
                        Title            = "Policy applies only to $Targeted and can be sidestepped from other platforms"
                        Description      = 'A sign-in that presents itself as a platform this policy does not list, such as Linux or an unrecognized device type, is not subject to its requirements. The platform a device reports is easily changed and attackers routinely try alternatives to find one that is not covered.'
                        Remediation      = 'Apply the policy to all platforms, or block sign-ins from unsupported and unknown platforms with a companion policy.'
                        AffectedPolicies = @($Policy.displayName)
                        CaTemplate       = "$($Context.Data.Reference.templates.blockUnsupportedPlatforms)"
                        DocumentationUrl = 'https://learn.microsoft.com/entra/identity/conditional-access/policy-all-users-device-unknown-unsupported'
                    }
                }
                $Findings.Add((New-CIPPCAGapFinding @Params))
            }
        }

        $HasClientFilter = ($ClientAppTypes.Count -gt 0) -and -not ($ClientAppTypes -contains 'all')
        if ($HasClientFilter) {
            $HasBrowser = $ClientAppTypes -contains 'browser'
            $HasMobile = $ClientAppTypes -contains 'mobileAppsAndDesktopClients'
            if ($RequiresMfa -and (-not $HasBrowser -or -not $HasMobile)) {
                $Missing = [System.Collections.Generic.List[string]]::new()
                if (-not $HasBrowser) { $Missing.Add('web browsers') }
                if (-not $HasMobile) { $Missing.Add('desktop and mobile apps') }
                $MissingText = $Missing -join ' and '
                $Params = @{
                    Severity         = 'Medium'
                    Category         = 'Platform coverage'
                    Title            = "Multifactor policy does not cover sign-ins from $MissingText"
                    Description      = "The multifactor requirement in this policy applies only to some kinds of client ($($ClientAppTypes -join ', ')). Anyone can choose a client of an uncovered kind and sign in with a password alone."
                    Remediation      = 'Apply the multifactor requirement to both web browsers and desktop and mobile apps, and block the older sign-in methods separately.'
                    AffectedPolicies = @($Policy.displayName)
                    DocumentationUrl = 'https://learn.microsoft.com/entra/identity/conditional-access/concept-conditional-access-conditions#client-apps'
                }
                $Findings.Add((New-CIPPCAGapFinding @Params))
            }
        }
    }

    $BlocksUnknownPlatforms = @($Context.Enabled | Where-Object {
            $Platforms = $_.conditions.platforms
            ($null -ne $Platforms) -and (@($Platforms.includePlatforms) -contains 'all') -and (@($Platforms.excludePlatforms).Count -gt 0) -and (@($_.grantControls.builtInControls) -contains 'block')
        }).Count -gt 0
    $MfaPoliciesUseSpecificPlatforms = @($Context.Enabled | Where-Object {
            $Platforms = $_.conditions.platforms
            if ($null -eq $Platforms -or @($Platforms.includePlatforms).Count -eq 0) { return $false }
            $RequiresMfa = (@($_.grantControls.builtInControls) -contains 'mfa') -or ($null -ne $_.grantControls.authenticationStrength)
            $RequiresMfa -and -not (@($Platforms.includePlatforms) -contains 'all')
        }).Count -gt 0

    if ($MfaPoliciesUseSpecificPlatforms -and -not $BlocksUnknownPlatforms) {
        $Params = @{
            Severity         = 'High'
            Category         = 'Platform coverage'
            Title            = 'Platform-limited multifactor policies leave unknown platforms open'
            Description      = 'One or more enforced multifactor policies apply only to specific device platforms, and nothing blocks sign-ins from platforms that are unsupported or unrecognized. A device that reports itself as an unlisted platform can sign in with a password alone.'
            Remediation      = 'Apply the multifactor policies to all platforms, or block sign-ins from unsupported and unknown platforms with a companion policy.'
            CaTemplate       = "$($Context.Data.Reference.templates.blockUnsupportedPlatforms)"
            DocumentationUrl = 'https://learn.microsoft.com/entra/identity/conditional-access/policy-all-users-device-unknown-unsupported'
        }
        $Findings.Add((New-CIPPCAGapFinding @Params))
    }

    @($Findings)
}
