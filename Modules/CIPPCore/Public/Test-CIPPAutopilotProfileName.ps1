function Test-CIPPAutopilotProfileName {
    <#
    .SYNOPSIS
        Validates an Autopilot deployment profile name against the character set Intune accepts.
    .DESCRIPTION
        Intune only accepts letters, numbers, spaces and the special characters : " ? . @ $ & _ [ ] { } | \
        in a deployment profile name. Anything else (a hyphen being the common one) is rejected by the
        service with a generic 500 that carries no reason, so we check up front to return a usable error.
        Leading and trailing spaces are allowed.
    .OUTPUTS
        PSCustomObject with IsValid and Message properties. Message is empty when the name is valid.
    #>
    [CmdletBinding()]
    param(
        [string]$DisplayName
    )

    $AllowedPattern = '^[\p{L}\p{N} :"?.@$&_\[\]{}|\\]+$'

    if ([string]::IsNullOrWhiteSpace($DisplayName)) {
        $Message = 'Autopilot profile name is required.'
    } elseif ($DisplayName -notmatch $AllowedPattern) {
        $Message = 'Autopilot profile name contains characters Intune does not accept. Only letters, numbers, spaces and : " ? . @ $ & _ [ ] { } | \ are allowed.'
    } else {
        $Message = ''
    }

    return [PSCustomObject]@{
        IsValid = [string]::IsNullOrEmpty($Message)
        Message = $Message
    }
}
