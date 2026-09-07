function Test-CIPPPIMRoleSettingsFloor {
    <#
    .SYNOPSIS
        Validates PIM role settings against CIPP's secure floor.

    .DESCRIPTION
        Pure validation shared by the PIM role-settings template endpoints (a template below the
        floor is rejected, not clamped), the PIMRoleSettings standard (a stored template is
        re-checked at run time so a hand-edited table row cannot weaken a tenant) and the policy
        summary shown on the Roles pages (a tenant's live policy is graded against the same floor).

        The floor:
          - activation (Expiration_EndUser_Assignment) must expire; maximum PT24H. Above PT8H is
            allowed but reported as a warning so the override is visible in the logbook.
          - activation must require MFA, or an authentication context (the two are mutually
            exclusive in Entra, so one of them is enough).
          - activation must require a justification.
          - eligibility (Expiration_Admin_Eligibility) must expire; maximum P365D.
          - active assignments (Expiration_Admin_Assignment) must expire; maximum P365D. This is what
            stops permanent active assignments being created in the portal as well as in CIPP.
          - active assignments must require a justification.
          - approval is optional, but when required at least one approver must be named.
          - notification recipients, when given, must be e-mail addresses with a valid level.

    .PARAMETER Settings
        The canonical settings object (see ConvertTo-CIPPPIMRoleSettings). A $null duration means
        "no expiration" and fails the floor.

    .OUTPUTS
        PSCustomObject: Valid (bool), Errors (string[]), Warnings (string[]).

    .FUNCTIONALITY
        Internal
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [AllowNull()]
        $Settings
    )

    $Errors = [System.Collections.Generic.List[string]]::new()
    $Warnings = [System.Collections.Generic.List[string]]::new()

    if ($null -eq $Settings) {
        $Errors.Add('No settings supplied.')
        return [PSCustomObject]@{ Valid = $false; Errors = @($Errors); Warnings = @($Warnings) }
    }

    function Test-FloorBool {
        param($Value)
        if ($Value -is [bool]) { return $Value }
        if ($null -eq $Value) { return $false }
        return ("$Value" -match '^(true|1|yes)$')
    }

    function Get-FloorSpan {
        param([string]$Value, [string]$Name, [string]$Max, [string]$Describe)
        if ([string]::IsNullOrWhiteSpace($Value)) {
            $Errors.Add("$Describe must expire ($Name is empty - a permanent/no-expiration setting is below the secure floor).")
            return $null
        }
        try {
            $Span = [System.Xml.XmlConvert]::ToTimeSpan($Value)
        } catch {
            $Errors.Add("$Describe`: '$Value' is not a valid ISO 8601 duration ($Name).")
            return $null
        }
        if ($Span -le [timespan]::Zero) {
            $Errors.Add("$Describe`: '$Value' must be greater than zero ($Name).")
            return $null
        }
        $MaxSpan = [System.Xml.XmlConvert]::ToTimeSpan($Max)
        if ($Span -gt $MaxSpan) {
            $Errors.Add("$Describe`: '$Value' exceeds the maximum of $Max ($Name).")
            return $null
        }
        return $Span
    }

    # Activation (end-user assignment)
    $ActivationSpan = Get-FloorSpan -Value $Settings.activationMaxDuration -Name 'activationMaxDuration' -Max 'PT24H' -Describe 'Role activation'
    if ($ActivationSpan -and $ActivationSpan -gt [System.Xml.XmlConvert]::ToTimeSpan('PT8H')) {
        $Warnings.Add("Role activation maximum '$($Settings.activationMaxDuration)' exceeds the recommended PT8H.")
    }

    $Requires = "$($Settings.activationRequires)"
    switch ($Requires) {
        'MFA' { }
        'AuthenticationContext' {
            if ("$($Settings.authenticationContextClaimValue)" -notmatch '^c\d{1,2}$') {
                $Errors.Add("Activation with an authentication context needs a claim value such as 'c1' (authenticationContextClaimValue).")
            }
        }
        default {
            $Errors.Add("Role activation must require MFA or an authentication context (activationRequires is '$Requires').")
        }
    }

    if (-not (Test-FloorBool $Settings.activationRequiresJustification)) {
        $Errors.Add('Role activation must require a justification (activationRequiresJustification).')
    }

    if ((Test-FloorBool $Settings.activationRequiresApproval) -and [string]::IsNullOrWhiteSpace("$($Settings.approvers)")) {
        $Errors.Add('Approval is required but no approvers are named (approvers).')
    }

    # Admin eligibility / assignment
    $null = Get-FloorSpan -Value $Settings.eligibilityMaxDuration -Name 'eligibilityMaxDuration' -Max 'P365D' -Describe 'Eligible assignments'
    $null = Get-FloorSpan -Value $Settings.activeAssignmentMaxDuration -Name 'activeAssignmentMaxDuration' -Max 'P365D' -Describe 'Active assignments'

    if (-not (Test-FloorBool $Settings.activeAssignmentRequiresJustification)) {
        $Errors.Add('Creating an active assignment must require a justification (activeAssignmentRequiresJustification).')
    }

    # Notifications
    $Recipients = @("$($Settings.notificationRecipients)" -split '[,;]' | ForEach-Object { $_.Trim() } | Where-Object { $_ })
    if ($Recipients.Count -gt 0) {
        foreach ($Recipient in $Recipients) {
            if ($Recipient -notmatch '^[^@\s]+@[^@\s]+\.[^@\s]+$') {
                $Errors.Add("'$Recipient' is not a valid notification e-mail address (notificationRecipients).")
            }
        }
        if ("$($Settings.notificationLevel)" -notin @('All', 'Critical')) {
            $Errors.Add("notificationLevel must be 'All' or 'Critical' when recipients are set (found '$($Settings.notificationLevel)').")
        }
    }

    return [PSCustomObject]@{
        Valid    = ($Errors.Count -eq 0)
        Errors   = @($Errors)
        Warnings = @($Warnings)
    }
}
