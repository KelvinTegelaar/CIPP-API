function Test-CippTransientError {
    <#
    .SYNOPSIS
        Returns true when an error message describes a transient upstream condition.
    .DESCRIPTION
        Recognises common transient failure signatures (HTTP 429/502/503/504, timeouts,
        Exchange Hygiene DAL / domain controller churn, generic send failures) so callers
        can log those at a lower severity than a genuine error and avoid alert noise.
    .FUNCTIONALITY
        Internal
    .PARAMETER Message
        The error message text to inspect.
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param (
        [Parameter(Mandatory = $false)]
        [AllowNull()]
        [AllowEmptyString()]
        [string]$Message
    )

    if ([string]::IsNullOrWhiteSpace($Message)) {
        return $false
    }

    $Patterns = @(
        'status code does not indicate success: (429|502|503|504)',
        'timed out',
        'an error occurred while sending the request',
        'TransientDALException',
        'ADServerSettingsChangedException',
        'temporarily unavailable',
        'too many requests',
        'ServerBusy'
    )

    foreach ($Pattern in $Patterns) {
        if ($Message -match "(?i)$Pattern") {
            return $true
        }
    }

    return $false
}
