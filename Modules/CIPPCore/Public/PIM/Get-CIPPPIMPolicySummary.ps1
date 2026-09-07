function Get-CIPPPIMPolicySummary {
    <#
    .SYNOPSIS
        Summarises PIM role settings for display and grades them against the secure floor.

    .PARAMETER Settings
        Canonical settings (ConvertTo-CIPPPIMRoleSettings or ConvertFrom-CIPPPIMPolicyRules output).

    .OUTPUTS
        PSCustomObject with SummaryText (e.g. "Activation <= 8h | MFA | Justification | Eligibility <= 1y
        | Active <= 6mo"), the individual flags, BelowFloor and FloorIssues.

    .FUNCTIONALITY
        Internal
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [AllowNull()]
        $Settings
    )

    function ConvertTo-FriendlyDuration {
        param([string]$Iso)
        if ([string]::IsNullOrWhiteSpace($Iso)) { return $null }
        try { $Span = [System.Xml.XmlConvert]::ToTimeSpan($Iso) } catch { return $Iso }
        if ($Span.TotalDays -ge 365 -and ($Span.TotalDays % 365) -eq 0) { return "$([int]($Span.TotalDays / 365))y" }
        if ($Span.TotalDays -ge 30 -and ($Span.TotalDays % 30) -eq 0) { return "$([int]($Span.TotalDays / 30))mo" }
        if ($Span.TotalDays -ge 1 -and $Span.TotalDays -eq [math]::Floor($Span.TotalDays)) { return "$([int]$Span.TotalDays)d" }
        if ($Span.TotalHours -ge 1 -and $Span.TotalHours -eq [math]::Floor($Span.TotalHours)) { return "$([int]$Span.TotalHours)h" }
        return "$([int]$Span.TotalMinutes)m"
    }

    if ($null -eq $Settings) {
        return [PSCustomObject]@{
            SummaryText                        = 'No PIM policy'
            MaxActivation                      = $null
            RequiresMfa                        = $false
            RequiresAuthenticationContext      = $false
            RequiresJustification              = $false
            RequiresTicket                     = $false
            RequiresApproval                   = $false
            EligibilityExpirationRequired      = $false
            ActiveAssignmentExpirationRequired = $false
            BelowFloor                         = $true
            FloorIssues                        = @('No PIM policy found for this role.')
        }
    }

    $Parts = [System.Collections.Generic.List[string]]::new()
    $Activation = ConvertTo-FriendlyDuration $Settings.activationMaxDuration
    $Parts.Add($(if ($Activation) { "Activation <= $Activation" } else { 'Activation unlimited' }))
    switch ("$($Settings.activationRequires)") {
        'MFA' { $Parts.Add('MFA') }
        'AuthenticationContext' { $Parts.Add("Auth context $($Settings.authenticationContextClaimValue)") }
        default { $Parts.Add('No MFA') }
    }
    $Parts.Add($(if ($Settings.activationRequiresJustification) { 'Justification' } else { 'No justification' }))
    if ($Settings.activationRequiresTicket) { $Parts.Add('Ticket') }
    if ($Settings.activationRequiresApproval) { $Parts.Add('Approval') }
    $Eligibility = ConvertTo-FriendlyDuration $Settings.eligibilityMaxDuration
    $Parts.Add($(if ($Eligibility) { "Eligibility <= $Eligibility" } else { 'Permanent eligibility allowed' }))
    $Active = ConvertTo-FriendlyDuration $Settings.activeAssignmentMaxDuration
    $Parts.Add($(if ($Active) { "Active <= $Active" } else { 'Permanent active allowed' }))

    $Floor = Test-CIPPPIMRoleSettingsFloor -Settings $Settings

    [PSCustomObject]@{
        SummaryText                        = ($Parts -join ' | ')
        MaxActivation                      = $Settings.activationMaxDuration
        RequiresMfa                        = ("$($Settings.activationRequires)" -eq 'MFA')
        RequiresAuthenticationContext      = ("$($Settings.activationRequires)" -eq 'AuthenticationContext')
        RequiresJustification              = [bool]$Settings.activationRequiresJustification
        RequiresTicket                     = [bool]$Settings.activationRequiresTicket
        RequiresApproval                   = [bool]$Settings.activationRequiresApproval
        EligibilityExpirationRequired      = -not [string]::IsNullOrWhiteSpace($Settings.eligibilityMaxDuration)
        ActiveAssignmentExpirationRequired = -not [string]::IsNullOrWhiteSpace($Settings.activeAssignmentMaxDuration)
        BelowFloor                         = -not $Floor.Valid
        FloorIssues                        = @($Floor.Errors)
    }
}
