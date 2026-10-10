function Test-CIPPCAGapDeviceRegistrationBypass {
    <#
    .SYNOPSIS
        Finds policies that try to protect device registration with controls the Device Registration Service
        ignores.
    .DESCRIPTION
        The Device Registration Service only honors MFA / authentication strength grant controls (MSRC
        VULN-153600, by design).
    .FUNCTIONALITY
        Internal
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        $Context
    )

    $Findings = [System.Collections.Generic.List[object]]::new()
    $DrsId = "$($Context.Data.DeviceRegistrationResource.resourceId)"
    $RegisterAction = "$($Context.Data.Reference.registerDeviceAction)"

    $RequiresMfa = {
        param($P)
        (@($P.grantControls.builtInControls) -contains 'mfa') -or ($null -ne $P.grantControls.authenticationStrength)
    }

    foreach ($Policy in @($Context.Policies)) {
        if ($Policy.state -eq 'disabled') { continue }

        $Apps = $Policy.conditions.applications
        $Controls = @($Policy.grantControls.builtInControls)
        $Locations = $Policy.conditions.locations

        $ExplicitlyTargetsRegistration = (@($Apps.includeApplications) -contains $DrsId) -or (@($Apps.includeUserActions) -contains $RegisterAction)
        $TargetsAllApps = @($Apps.includeApplications) -contains 'All'
        if (-not $ExplicitlyTargetsRegistration -and -not $TargetsAllApps) { continue }

        $UsesLocationCondition = ($null -ne $Locations) -and ((@($Locations.includeLocations).Count -gt 0) -or (@($Locations.excludeLocations).Count -gt 0))
        $RequiresCompliantDevice = ($Controls -contains 'compliantDevice') -or ($Controls -contains 'domainJoinedDevice')
        if (-not $UsesLocationCondition -and -not $RequiresCompliantDevice) { continue }
        if (& $RequiresMfa $Policy) { continue }

        $HasRegistrationMfaPolicy = $false
        foreach ($Other in @($Context.Policies)) {
            if ($Other.id -eq $Policy.id -or $Other.state -eq 'disabled') { continue }
            $OtherApps = $Other.conditions.applications
            $CoversRegistration = (@($OtherApps.includeUserActions) -contains $RegisterAction) -or (@($OtherApps.includeApplications) -contains $DrsId)
            if ($CoversRegistration -and (& $RequiresMfa $Other)) { $HasRegistrationMfaPolicy = $true; break }
        }
        if ($HasRegistrationMfaPolicy) { continue }

        $Blocks = $Controls -contains 'block'
        $Issues = [System.Collections.Generic.List[string]]::new()
        if ($UsesLocationCondition) { $Issues.Add('network location conditions') }
        if ($RequiresCompliantDevice) { $Issues.Add('a managed-device requirement') }
        $IssueText = $Issues -join ' and '

        $Framing = if ($Blocks) {
            "This policy blocks access based on $IssueText, but the device registration service ignores those conditions. New devices can therefore still be registered, for example from an untrusted network."
        } else {
            "This policy relies on $IssueText, but the device registration service ignores those conditions and only responds to a multifactor requirement."
        }

        $Params = @{
            Severity         = if ($ExplicitlyTargetsRegistration) { 'High' } else { 'Medium' }
            Category         = 'Device registration'
            Title            = if ($ExplicitlyTargetsRegistration) { 'Device registration is protected only by conditions the service ignores' } else { 'Device registration is not covered by the conditions of this policy' }
            Description      = "$Framing No other enforced policy requires multifactor authentication when a device is registered, so anyone with a valid password can register a device that may then count as trusted."
            Remediation      = 'Require multifactor authentication for registering or joining devices through a dedicated policy, since network and device conditions do not protect this step.'
            AffectedPolicies = @($Policy.displayName)
            RelatedIds       = @($DrsId)
            CaTemplate       = "$($Context.Data.Reference.templates.registerSecurityInfo)"
            DocumentationUrl = 'https://learn.microsoft.com/entra/identity/conditional-access/policy-all-users-device-registration'
        }
        $Findings.Add((New-CIPPCAGapFinding @Params))
    }

    @($Findings)
}
