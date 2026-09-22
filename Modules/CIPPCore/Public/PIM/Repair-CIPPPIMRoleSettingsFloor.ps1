function Repair-CIPPPIMRoleSettingsFloor {
    <#
    .SYNOPSIS
        Raises captured PIM role settings to CIPP's secure floor, reporting every change.

    .DESCRIPTION
        Used when a template is created from a role's current settings in a tenant
        (ConvertFrom-CIPPPIMPolicyRules output). A tenant's live policy may sit below the secure
        floor - permanent eligibility or active assignments, activation without MFA - and a
        template must never store that, so each offending value is replaced with the closest value
        the floor allows and the change is returned as an adjustment for the caller to surface.
        Settings already at or above the floor pass through untouched, so capturing a compliant
        role is an exact copy.

        This is the one deliberate exception to "reject, never adjust": templates typed in by an
        administrator are still rejected outright (Test-CIPPPIMRoleSettingsFloor); only a capture
        of what a tenant already has is raised, because the tenant's own values are the input and
        refusing them would make capture useless on any tenant still on Entra's defaults.

    .PARAMETER Settings
        The canonical settings object, as returned by ConvertFrom-CIPPPIMPolicyRules.

    .OUTPUTS
        PSCustomObject: Settings (the repaired copy), Adjustments (string[] describing each raise).

    .FUNCTIONALITY
        Internal
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        $Settings
    )

    $Adjustments = [System.Collections.Generic.List[string]]::new()

    function Repair-Duration {
        param([string]$Value, [string]$Max, [string]$Describe)
        if ([string]::IsNullOrWhiteSpace($Value)) {
            $Adjustments.Add("$Describe did not require an expiration (permanent allowed); set to $Max.")
            return $Max
        }
        $Span = try { [System.Xml.XmlConvert]::ToTimeSpan($Value) } catch { $null }
        if ($null -eq $Span -or $Span -le [timespan]::Zero) {
            $Adjustments.Add("$Describe had an unusable duration '$Value'; set to $Max.")
            return $Max
        }
        if ($Span -gt [System.Xml.XmlConvert]::ToTimeSpan($Max)) {
            $Adjustments.Add("$Describe allowed '$Value', above the floor maximum; lowered to $Max.")
            return $Max
        }
        return $Value
    }

    $ActivationRequires = "$($Settings.activationRequires)"
    $ClaimValue = "$($Settings.authenticationContextClaimValue)"
    if ($ActivationRequires -eq 'AuthenticationContext' -and $ClaimValue -notmatch '^c\d{1,2}$') {
        $Adjustments.Add("Activation used an authentication context without a usable claim value ('$ClaimValue'); switched to requiring MFA.")
        $ActivationRequires = 'MFA'
        $ClaimValue = ''
    } elseif ($ActivationRequires -notin @('MFA', 'AuthenticationContext')) {
        $Adjustments.Add('Activation did not require MFA or an authentication context; set to require MFA.')
        $ActivationRequires = 'MFA'
        $ClaimValue = ''
    }

    $ActivationJustification = $Settings.activationRequiresJustification -eq $true
    if (-not $ActivationJustification) {
        $Adjustments.Add('Activation did not require a justification; enabled it.')
        $ActivationJustification = $true
    }

    $RequiresApproval = $Settings.activationRequiresApproval -eq $true
    $Approvers = "$($Settings.approvers)"
    if ($RequiresApproval -and [string]::IsNullOrWhiteSpace($Approvers)) {
        $Adjustments.Add('Activation required approval but no approver could be captured; approval disabled.')
        $RequiresApproval = $false
    }

    $ActiveJustification = $Settings.activeAssignmentRequiresJustification -eq $true
    if (-not $ActiveJustification) {
        $Adjustments.Add('Creating an active assignment did not require a justification; enabled it.')
        $ActiveJustification = $true
    }

    $Recipients = @("$($Settings.notificationRecipients)" -split '[,;]' | ForEach-Object { $_.Trim() } | Where-Object { $_ })
    $ValidRecipients = @($Recipients | Where-Object { $_ -match '^[^@\s]+@[^@\s]+\.[^@\s]+$' })
    if ($ValidRecipients.Count -lt $Recipients.Count) {
        $Dropped = @($Recipients | Where-Object { $_ -notin $ValidRecipients })
        $Adjustments.Add("Dropped notification recipient(s) that are not e-mail addresses: $($Dropped -join ', ').")
    }
    $NotificationLevel = "$($Settings.notificationLevel)"
    if ($ValidRecipients.Count -gt 0 -and $NotificationLevel -notin @('All', 'Critical')) {
        $Adjustments.Add("Notification level '$NotificationLevel' is not valid; set to 'All'.")
        $NotificationLevel = 'All'
    }

    $Repaired = [PSCustomObject]@{
        activationMaxDuration                 = Repair-Duration -Value $Settings.activationMaxDuration -Max 'PT24H' -Describe 'Role activation'
        activationRequires                    = $ActivationRequires
        authenticationContextClaimValue       = $ClaimValue
        activationRequiresJustification       = $ActivationJustification
        activationRequiresTicket              = $Settings.activationRequiresTicket -eq $true
        activationRequiresApproval            = $RequiresApproval
        approvers                             = if ($RequiresApproval) { $Approvers } else { '' }
        eligibilityMaxDuration                = Repair-Duration -Value $Settings.eligibilityMaxDuration -Max 'P365D' -Describe 'Eligible assignments'
        activeAssignmentMaxDuration           = Repair-Duration -Value $Settings.activeAssignmentMaxDuration -Max 'P365D' -Describe 'Active assignments'
        activeAssignmentRequiresMfa           = $Settings.activeAssignmentRequiresMfa -eq $true
        activeAssignmentRequiresJustification = $ActiveJustification
        notificationRecipients                = ($ValidRecipients -join ', ')
        notificationLevel                     = if ([string]::IsNullOrWhiteSpace($NotificationLevel)) { 'All' } else { $NotificationLevel }
    }

    return [PSCustomObject]@{
        Settings    = $Repaired
        Adjustments = @($Adjustments)
    }
}
