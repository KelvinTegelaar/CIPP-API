function Test-CIPPCacheCapabilityError {
    <#
    .SYNOPSIS
        Returns $true when a cache-collection exception reflects a benign tenant condition
        rather than a real fault.

    .DESCRIPTION
        License gating (Push-CIPPDBCacheData) skips whole collection groups a tenant is not
        licensed for, but it cannot detect a service that is licensed yet not provisioned - for
        example a Business Premium tenant that holds a Defender for Business (MDE_SMB) plan but
        has never onboarded a device to Defender for Endpoint. Those endpoints answer with
        'No active license found' and similar, which is an expected state rather than an error
        worth surfacing to an MSP.

        Collectors pass their caught exception message here to decide log severity: a match is
        logged at Debug and treated as a clean skip; anything else stays an Error.

    .PARAMETER Message
        The exception message to classify.

    .FUNCTIONALITY
        Internal

    .EXAMPLE
        $Sev = if (Test-CIPPCacheCapabilityError -Message $_.Exception.Message) { 'Debug' } else { 'Error' }
    #>
    [OutputType([bool])]
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [AllowEmptyString()]
        [string]$Message
    )

    if ([string]::IsNullOrWhiteSpace($Message)) { return $false }

    # High-confidence 'tenant lacks or has not provisioned this capability' signals. Kept
    # deliberately specific so a genuine failure is never silently downgraded to Debug.
    $BenignPatterns = @(
        'No active license found'
        'not licensed'
        'does not have a valid'
        '(is )?not onboarded'
        'license.{0,20}(is )?(required|not found|missing)'
    )

    foreach ($Pattern in $BenignPatterns) {
        if ($Message -match $Pattern) { return $true }
    }
    return $false
}
