function Get-CippTeamsNumberType {
    <#
    .SYNOPSIS
        Normalizes a Teams phone number type to the casing the Graph API expects.

    .DESCRIPTION
        The Teams ConfigAPI number list returns PascalCase ('DirectRouting'), while the
        teamsAdministration Graph actions expect the camelCase enum ('directRouting').
        Unknown values are passed through unchanged so the service can reject them with a
        meaningful error rather than us silently guessing.

    .FUNCTIONALITY
        Internal
    #>
    [CmdletBinding()]
    param(
        [string] $NumberType
    )

    # switch is case-insensitive by default
    switch ($NumberType) {
        'DirectRouting' { return 'directRouting' }
        'CallingPlan' { return 'callingPlan' }
        'OperatorConnect' { return 'operatorConnect' }
        default { return $NumberType }
    }
}
