function Test-CIPPCAGapGuestAuthStrength {
    <#
    .SYNOPSIS
        Advises on Cross-Tenant Access Settings when guests are required to satisfy MFA or an authentication
        strength.
    .DESCRIPTION
        Requiring MFA for guests is best practice, not a weakness, so this is an Info-level operational
        advisory: guest users authenticate in their home tenant and are blocked unless inbound MFA trust is
        configured.
    .FUNCTIONALITY
        Internal
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        $Context
    )

    $Findings = [System.Collections.Generic.List[object]]::new()

    foreach ($Policy in @($Context.Policies)) {
        if ($Policy.state -eq 'disabled') { continue }
        $Users = $Policy.conditions.users
        $Grant = $Policy.grantControls
        $TargetsGuests = (@($Users.includeUsers) -contains 'GuestsOrExternalUsers') -or ($null -ne $Users.includeGuestsOrExternalUsers)
        $RequiresAuthStrength = $null -ne $Grant.authenticationStrength
        $RequiresMfa = @($Grant.builtInControls) -contains 'mfa'
        if (-not $TargetsGuests -or (-not $RequiresAuthStrength -and -not $RequiresMfa)) { continue }

        $StrengthType = 'MFA'
        if ($RequiresAuthStrength) {
            $StrengthName = if ($Grant.authenticationStrength.displayName) { "$($Grant.authenticationStrength.displayName)" } else { 'Unknown' }
            $StrengthType = if (Test-CIPPCAPolicyPhishingResistant -Policy $Policy -Context $Context) { 'Phishing-resistant MFA' } else { "the ""$StrengthName"" authentication strength" }
        }

        $GuestTypes = [System.Collections.Generic.List[string]]::new()
        if ($null -ne $Users.includeGuestsOrExternalUsers) {
            $TypeString = "$($Users.includeGuestsOrExternalUsers.guestOrExternalUserTypes)"
            if ($TypeString.Contains('b2bCollaborationGuest')) { $GuestTypes.Add('B2B Collaboration guests') }
            if ($TypeString.Contains('b2bCollaborationMember')) { $GuestTypes.Add('B2B Collaboration members') }
            if ($TypeString.Contains('b2bDirectConnectUser')) { $GuestTypes.Add('B2B Direct Connect users') }
            if ($TypeString.Contains('internalGuest')) { $GuestTypes.Add('Internal guests') }
            if ($TypeString.Contains('serviceProvider')) { $GuestTypes.Add('Service provider users') }
        }
        $GuestTypeText = if ($GuestTypes.Count -gt 0) { $GuestTypes -join ', ' } else { 'all guest and external users' }

        $PhishingNote = if ($RequiresAuthStrength -and $StrengthType -eq 'Phishing-resistant MFA') {
            ' Few organizations have phishing-resistant methods rolled out, so guests can only meet this requirement if their home organization supports such methods and this tenant trusts the result.'
        } else { '' }

        $Params = @{
            Severity         = 'Info'
            Category         = 'Guest coverage'
            Title            = 'Guest multifactor requirement depends on trusting their home organization'
            Description      = "This policy requires $StrengthType from $GuestTypeText. Guests prove their identity in their home organization rather than here, so they can only meet this requirement if this tenant is set to trust the multifactor authentication their home organization performed. Until that trust is in place, guests are blocked even after completing multifactor authentication at home.$PhishingNote"
            Remediation      = 'Trust the multifactor authentication performed by the home organizations of your guests in the cross-tenant access settings, for all external organizations or per partner, and verify with a guest sign-in before enforcing.'
            AffectedPolicies = @($Policy.displayName)
            DocumentationUrl = 'https://learn.microsoft.com/entra/external-id/authentication-conditional-access'
        }
        $Findings.Add((New-CIPPCAGapFinding @Params))
    }

    @($Findings)
}
